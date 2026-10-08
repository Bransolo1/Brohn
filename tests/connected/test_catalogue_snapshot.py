"""Real SQLite WAL regression; no application, child process or server launches."""
from pathlib import Path
import hashlib,json,sqlite3,tempfile,unittest
from catalogue_snapshot import copy_catalogue

def snapshot(root):
    return [dict(path=p.relative_to(root).as_posix(),bytes=p.stat().st_size,
      sha256=hashlib.sha256(p.read_bytes()).hexdigest()) for p in sorted(root.rglob('*')) if p.is_file()]

class CatalogueSnapshot(unittest.TestCase):
    def test_committed_wal_is_read_without_changing_originals(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);original=root/'original';original.mkdir();db=original/'catalog.sqlite'
            writer=sqlite3.connect(db);reader=None
            try:
                self.assertEqual(writer.execute('PRAGMA journal_mode=WAL').fetchone()[0],'wal')
                writer.execute('PRAGMA wal_autocheckpoint=0')
                writer.execute('CREATE TABLE evidence(id TEXT PRIMARY KEY, original_json TEXT NOT NULL)');writer.commit()
                writer.execute('PRAGMA wal_checkpoint(TRUNCATE)')
                value='{"clock":"1234.567890123","value":7}'
                writer.execute('INSERT INTO evidence VALUES(?,?)',('committed-only-in-wal',value));writer.commit()
                self.assertGreater((original/'catalog.sqlite-wal').stat().st_size,0)
                # Demonstrate the regression: immutable main-file reading misses
                # the committed WAL value. Never apply this reader to user data.
                main_only=sqlite3.connect(db.as_uri()+'?mode=ro&immutable=1',uri=True)
                self.assertEqual(main_only.execute('SELECT count(*) FROM evidence').fetchone()[0],0);main_only.close()
                before=snapshot(original)
                copied,receipt=copy_catalogue(original,root/'copied',before)
                self.assertEqual({row["path"]:row for row in receipt},{row["path"]:row for row in before})
                self.assertEqual(snapshot(original),before)
                reader=sqlite3.connect(copied.as_uri()+'?mode=ro',uri=True);reader.execute('PRAGMA query_only=ON')
                self.assertEqual(reader.execute('SELECT id,original_json FROM evidence').fetchall(),[('committed-only-in-wal',value)])
                with self.assertRaises(sqlite3.OperationalError):reader.execute("INSERT INTO evidence VALUES('new','{}')")
                reader.close();reader=None
                self.assertEqual(snapshot(original),before)
            finally:
                if reader:reader.close()
                writer.close()

    def test_changed_original_and_nonfresh_destination_refuse(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);original=root/'original';original.mkdir();db=original/'catalog.sqlite';db.write_bytes(b'original')
            before=snapshot(original);db.write_bytes(b'changed')
            with self.assertRaisesRegex(ValueError,'bytes changed'):copy_catalogue(original,root/'changed-copy',before)
            with self.assertRaisesRegex(ValueError,'fresh snapshot'):copy_catalogue(original,original/'inside',snapshot(original))

if __name__=='__main__':unittest.main()
