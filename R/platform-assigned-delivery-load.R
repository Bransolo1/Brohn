# Explicit application-owned delivery closure, never read from a study/archive.
brohn_load_assigned_delivery <- function(envir = parent.frame()) {
  # Call ordinary brohn_load first. This ordered successor keeps every original
  # compiler/authority module distinct rather than flattening shared basenames.
  required <- list(
    list(path="R/assigned-domain/01-platform-method-evidence-binding.R", sha256="b42e378fd47fcf3e0bd752c07fbde0bc5fa740403b3fedd381b1d1d84404f846", bytes=20735L),
    list(path="R/assigned-domain/02-platform-method-evidence-ancestry.R", sha256="2e6638ac0588a60ed3ccf2c553adfd8b47ba09f803711c3be52ca2966c2593e5", bytes=9768L),
    list(path="R/assigned-domain/03-platform-method-evidence-identity.R", sha256="e70bed9311a88481a066ef04118a5c3bccd58201dae9d3e167f5049b83407e0a", bytes=13225L),
    list(path="R/assigned-domain/04-platform-method-evidence-domain.R", sha256="711a0427341cb518536248b87a9ce8ff6858599fe51c9d579a0704b0e021de42", bytes=7856L),
    list(path="R/assigned-domain/05-platform-variant-design.R", sha256="29ba8ba2e30a5b0913c4b3265a21592362a537d02345bb7b940fa2ff11a94748", bytes=12097L),
    list(path="R/assigned-domain/06-platform-variant-assignment.R", sha256="20b623a69f01b1a58ee3d66f46947b7b97c4a6422f954d79410d25184fb63b69", bytes=6081L),
    list(path="R/assigned-domain/07-platform-core.R", sha256="224b7c72a7c496fb0d2040bb876a4003ffb751fa26036c3a493bde72ce261ca9", bytes=34776L),
    list(path="R/assigned-domain/08-platform-question-revision.R", sha256="25d375e35c366c2ee40cfc797ed32a131f8de4d04f382852c2ff051eb0c9e82b", bytes=34060L),
    list(path="R/assigned-domain/09-platform-method-evidence-protocol.R", sha256="f703164216bfee6570b6a18a33e58b53a9d86c228e2cabed36a3523a6b4505e7", bytes=870L),
    list(path="R/assigned-domain/10-platform-variant-protocol.R", sha256="c2cba2e67bdf46498547ce103137503e998c9285b06974d9dc46383fcc261088", bytes=2506L),
    list(path="R/assigned-domain/11-platform-question-revision.R", sha256="65b378fe11470481c7c659ef7593679d00c575ebed252857d32fe58f4a9dacf0", bytes=34291L),
    list(path="R/assigned-domain/12-platform-task-protocol-history.R", sha256="6396717408c4c3f343d5d1126513eefd68f8f829e9f7abb41ee6ef64c7523266", bytes=25273L),
    list(path="R/assigned-domain/13-platform-method-evidence-protocol-history.R", sha256="b098990c344feec299c6ccab6cf5ce54401bedaeb233097e965d084547f43e98", bytes=16707L),
    list(path="R/assigned-domain/14-platform-variant-protocol-history.R", sha256="52e4f2c0a541205b7b323d5bb34515179e29948557f5ffad4f12f11ae2dd9c49", bytes=7102L),
    list(path="R/assigned-domain/15-platform-participant-question-projection.R", sha256="6b173ca5e42a5aa16be805d381527fe8bf83e177d61639f3ebde4b17d11d3589", bytes=12816L),
    list(path="R/assigned-domain/16-platform-participant-choice-projection.R", sha256="0103dd397816f3b9615aa081bf38e5d7d289ccba3f39b1df16e60c9bdf0dbade", bytes=9489L),
    list(path="R/assigned-domain/17-platform-participant-task-projection.R", sha256="ae28b6b5926a0b7ffd2f621737253c9ce7d8eaa651ee7a368fe30ac96aa85ccb", bytes=23222L),
    list(path="R/assigned-domain/18-platform-participant-view-projection.R", sha256="b6df86c245359a724a2f1dfb0110cffafbeb56c927a1f51d76cd5601b82fa843", bytes=11797L),
    list(path="R/assigned-domain/19-platform-participant-wire-json.R", sha256="059153bf17485421b497368a76ea41bac0a78eb99f91d2308b076d0d9386be69", bytes=3786L),
    list(path="R/assigned-domain/20-platform-participant-task-projection.R", sha256="e0dbb913b6b14e944f4cefe58e2c0d16e6b5d51fb83e502f525cc92de5e4fb88", bytes=23404L),
    list(path="R/assigned-domain/21-platform-participant-view-context.R", sha256="5f57fa449fc168c321417301ee3e6817a7dc114ddb2e5962a85c4f0fa21e21d4", bytes=26470L),
    list(path="R/assigned-domain/22-platform-participant-state-projection.R", sha256="978d34cc5f71c7de18ba444ddc0e8f74f39bdec81754cf44294bfaeb29c0883a", bytes=17021L),
    list(path="R/assigned-domain/23-platform-participant-received-bytes.R", sha256="663de1972a3cb27d2a05e07e2bc6bfce850c2439da8253fccb2907180e91cbdf", bytes=8430L),
    list(path="R/assigned-domain/24-platform-delivery.R", sha256="4b71ae3b92e4aa7db8cf3ad432d6fdca0056b0cb66411dab293e2e449b2282cf", bytes=58913L),
    list(path="R/assigned-domain/25-platform-participant-view-store.R", sha256="3839d19ff00cf617783d9ab3aedd35683cb63e1cd77da4b5e8c8299ebdaea4aa", bytes=46122L),
    list(path="R/assigned-domain/26-platform-participant-view-current.R", sha256="a35f43c897ea7ce76222b0eb2fa745234b5795b5a906a0b50ea3c1a6b2d5e9dc", bytes=14782L),
    list(path="R/assigned-domain/27-platform-participant-questionnaire-events.R", sha256="15091ea8449b05c7e5073e0828f74e048d8598e4df81a24b5b1356ec318f188e", bytes=4146L),
    list(path="R/assigned-domain/28-platform-participant-ordinary-events.R", sha256="99e6de6ba6d5efb544108c49a6c7763d240861a56e24f98804ee78d3f0fd1e73", bytes=13763L),
    list(path="R/assigned-domain/29-platform-participant-operation-documents.R", sha256="dad95ca94f57b08c3446a9dcd93f5dbe837d6d1d2bcf023448a998a8b2d4115f", bytes=13861L),
    list(path="R/assigned-domain/30-platform-participant-view-receive.R", sha256="1bf18797e3acc32a947be92fbeea16606cc530ffca1a1fbfea6a93ad4b87f030", bytes=37367L),
    list(path="R/assigned-domain/31-platform-participant-view-current.R", sha256="40b46b41defe822fcd5152dfa8d78cbb900c027fb0570a24db36aae9f75e47e6", bytes=15274L),
    list(path="R/assigned-domain/32-platform-participant-view-camera.R", sha256="58a864690a0f099a5f71e652364e4dc19cf7071d1eb67bbbd524312321aaba61", bytes=6249L),
    list(path="R/assigned-domain/33-platform-participant-view-resource.R", sha256="2811aefcd785647246f3e41da10d1e76563470a23d39d8d8848205ac6a1d4a48", bytes=2680L),
    list(path="R/assigned-domain/34-platform-participant-view-entry.R", sha256="97a8716ca0691ea2edd0a33d5208f21480cc53575fb4f207d7cbf8ce648608bc", bytes=4487L),
    list(path="R/assigned-domain/35-platform-participant-view-finish.R", sha256="a859a4f8cbe6f85c323d6528cbe72a3cdea28437e5b8b8fc13dfb6bed33d24d4", bytes=7666L),
    list(path="R/assigned-domain/36-platform-participant-view-http.R", sha256="e70552ea2ad52dc703f2d9d6cf39507321393c840d38b21ad4f7eb0c08ad4709", bytes=3840L),
    list(path="R/assigned-domain/37-platform-participant-view-router.R", sha256="22cfde77c4b14d7a5451f520bbe061b17f609d2d9bf9b50eac0e743830650534", bytes=6880L),
    list(path="R/assigned-domain/38-platform-participant-variant-finish.R", sha256="4c1bbf01fc03282ebfd26be94fe10790d5107992f495d50f35f5f16a3b5ea483", bytes=9093L),
    list(path="R/assigned-domain/39-platform-assigned-view-router.R", sha256="779689f394873714b27d960883585f2048f392190debf47be508e3a198f64eb1", bytes=5306L),
    list(path="R/platform-saved-analysis-dispatch.R", sha256="af3345d05fd2d8b0f0aed0c1ffca0758abfbf6218974acd790adeeab3e07f6ac", bytes=13627L),
    list(path="R/platform-saved-analysis-views.R", sha256="0f873746f95257900167d3125f8e0c7c84a2fcca58cf0371de6b1d47cb119b8e", bytes=2497L),
    list(path="R/assigned-authoring/R/platform-study-design.R", sha256="1277678bdbc6de51ccbe4f4c23ee4f169067a7e5ea211646982162750e725d0f", bytes=13160L),
    list(path="R/assigned-authoring/R/platform-stimulus-versions.R", sha256="ec5b6161557fab7b96a097a4800315e556f10b99d4096a3d8485368d7f0dbef7", bytes=2395L),
    list(path="R/assigned-authoring/R/platform-library.R", sha256="51596df361ebb369b3700fea61c861ecc2e39f6f440ff63b95af59f7d44208be", bytes=21306L),
    list(path="R/assigned-authoring/R/platform-portability.R", sha256="88637c3e7c488e2349b6e7cc98441f8d5753093cbcb2e5e236251332e5fd1ada", bytes=18419L),
    list(path="R/assigned-authoring/R/platform-materials.R", sha256="c71388e5ed7ed7400dbaceac9813f905b4d565c850e6d14ea762aaa8e14f87a2", bytes=5959L),
    list(path="R/assigned-authoring/R/platform-welcome.R", sha256="f660b4a91b33cdf24e792fd95dbccbb096cca260bd48269bcdac6b250f245ae1", bytes=3274L),
    list(path="R/assigned-authoring/R/platform-question-flow.R", sha256="1513e6018ccdcd4b06488680c60fca90d323147b22c726861d3d2faba9e406a3", bytes=8182L),
    list(path="R/assigned-authoring/R/platform-question-sections.R", sha256="2313196d7abc500ac62cc56c838f31c9d1e34101da5fb56f280180bf3518bf12", bytes=16196L),
    list(path="R/assigned-authoring/R/platform-question-revision-views.R", sha256="5812b1202fcc44854cbeb1fb989ad1cdb31f8dabaf6fdd63d7378c502033798c", bytes=4333L),
    list(path="R/assigned-authoring/R/platform-stimulus-assignment-views.R", sha256="73c38aa63398b4f43d92033cc7208bd3bd1c8d3b81646e1559b3191c8619dd3a", bytes=5157L),
    list(path="R/assigned-authoring/R/platform-stimulus-version-views.R", sha256="db58704fdd1acb413967b0c692699570dc5e364232e2879d8a627356309de821", bytes=7409L),
    list(path="R/assigned-authoring/R/platform-views.R", sha256="2e6da391645e89cfeac20b0ef02f58e78b99f453d61ebe602784ddcea93b0308", bytes=26455L),
    list(path="R/assigned-authoring/R/platform-app.R", sha256="17557d3d0e8842650f1eb571a46a36a047c197960b8c155a11f7b5938382ec24", bytes=58575L),
    list(path="R/assigned-authoring/R/platform-guidance-views.R", sha256="dc45ce3d91f88aa6418bcbb275cd8a1fcbe900d157f7ca219838fd08ea348ced", bytes=28537L)
  )
  verify <- function() for (item in required) {
    brohn_require(file.exists(item$path) && !dir.exists(item$path) &&
      file.info(item$path)$size == item$bytes &&
      identical(digest::digest(file = item$path, algo = "sha256"), item$sha256),
      "The installed participant service differs from its registered source. Restart a complete installation.")
  }
  verify()
  brohn_require(file.exists("R/assigned-authoring/scripts/portable-design.py") &&
    file.info("R/assigned-authoring/scripts/portable-design.py")$size == 16010 &&
    identical(digest::digest(file = "R/assigned-authoring/scripts/portable-design.py", algo = "sha256"), "76f2cddfd358075200c10f263c732362ab565bf662c398a6330886924af8ad03"),
    "The installed design portability helper differs from its application source.")
  if (exists(".brohn_assigned_delivery_loaded", envir, inherits = FALSE)) {
    brohn_require(identical(get(".brohn_assigned_delivery_loaded", envir, inherits = FALSE), required),
      "The participant service source changed during this session.")
    return(invisible(TRUE))
  }
  for (item in required) source(item$path, local = envir, encoding = "UTF-8")
  for (name in c("assigned-publish", "assigned-derivation", "assigned-service"))
    source(paste0("R/platform-", name, ".R"), local = envir, encoding = "UTF-8")
  get("brohn_install_assigned_runtime", envir = envir)("www/assigned-participant", envir)
  verify()
  assign(".brohn_assigned_delivery_loaded", required, envir)
  invisible(TRUE)
}
