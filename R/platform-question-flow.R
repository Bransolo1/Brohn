# Authoring helpers operate on the existing, executable display-logic AST.
brohn_flow_earlier <- function(design, question_id) {
  index <- match(question_id, brohn_ids(design$questions))
  brohn_require(!is.na(index), "Choose a question from this study.")
  target <- design$questions[[index]]
  earlier <- if (index > 1L) design$questions[seq_len(index-1L)] else list()
  scopes <- if (target$scope == "before") "before" else if (target$scope == "after_each") c("before", "after_each") else c("before", "end")
  Filter(function(q) q$scope %in% scopes, earlier)
}

brohn_flow_children <- function(rule) {
  if (is.null(rule)) return(list())
  if (rule$op %in% c("and", "or")) return(rule$rules)
  if (rule$op == "not") return(list(rule$rule))
  list()
}

brohn_flow_nodes <- function(rule, path = integer()) {
  if (is.null(rule)) return(list())
  result <- list(list(path = as.list(path), rule = rule))
  children <- brohn_flow_children(rule)
  for (i in seq_along(children)) result <- c(result, brohn_flow_nodes(children[[i]], c(path, i)))
  brohn_require(length(result) <= 200L, "This rule exceeds the 200-node visual editor limit. Simplify its authored groups before editing it here; the saved design remains unchanged.")
  result
}

brohn_flow_get <- function(rule, path = integer()) {
  path <- unlist(path, use.names = FALSE)
  for (index in path) {
    children <- brohn_flow_children(rule)
    brohn_require(brohn_number(index, 1, length(children), TRUE), "This rule position changed. Select it again.")
    rule <- children[[index]]
  }
  rule
}

brohn_flow_replace <- function(rule, path, replacement) {
  path <- unlist(path, use.names = FALSE)
  if (!length(path)) return(replacement)
  index <- path[[1L]]; children <- brohn_flow_children(rule)
  brohn_require(brohn_number(index, 1, length(children), TRUE), "This rule position changed. Select it again.")
  children[index] <- list(brohn_flow_replace(children[[index]], path[-1L], replacement))
  if (rule$op == "not") rule$rule <- children[[1L]] else rule$rules <- children
  rule
}

brohn_flow_remove <- function(rule, path) {
  path <- unlist(path, use.names = FALSE)
  if (!length(path)) return(NULL)
  parent_path <- head(path, -1L); parent <- brohn_flow_get(rule, parent_path); children <- brohn_flow_children(parent)
  index <- tail(path,1L); brohn_require(brohn_number(index,1,length(children),TRUE), "This rule position changed.")
  if (length(children)==1L) return(brohn_flow_remove(rule,parent_path))
  parent$rules <- children[-index]
  brohn_flow_replace(rule,parent_path,parent)
}

brohn_flow_move <- function(rule, path, direction) {
  path <- unlist(path,use.names=FALSE)
  brohn_require(length(path)>0L && direction %in% c(-1,1), "Choose an adjacent rule in the same group.")
  parent_path <- head(path,-1L); parent <- brohn_flow_get(rule,parent_path); children <- brohn_flow_children(parent)
  index <- tail(path,1L); next_index <- index+direction
  brohn_require(parent$op %in% c("and","or") && index %in% seq_along(children) && next_index %in% seq_along(children), "This condition has no sibling in that direction.")
  children[c(index,next_index)] <- children[c(next_index,index)]; parent$rules <- children
  brohn_flow_replace(rule,parent_path,parent)
}

brohn_flow_kind <- function(rule, kind, condition = NULL) {
  brohn_require(kind %in% c("condition","and","or","not"), "Choose an available rule type.")
  if (kind == "condition") {brohn_require(!is.null(condition), "Choose an answer condition."); return(condition)}
  brohn_require(!is.null(rule), "Add an answer condition before making a group.")
  if (kind == "not") return(if (rule$op == "not") rule else list(op="not",rule=rule))
  list(op=kind,rules=if (rule$op %in% c("and","or")) rule$rules else list(rule))
}

brohn_flow_operators <- function(question) {
  common <- c("Has an answer"="answered")
  if (question$type %in% c("rating","single_choice","dropdown","text","long_text","number","slider"))
    common <- c(common,"Equals"="equals","Does not equal (when answered)"="not_equals")
  if (question$type %in% c("number","slider") || (question$type == "rating" && all(vapply(question$options,function(o) brohn_number(o$value),logical(1)))))
    common <- c(common,"Is greater than"="greater","Is less than"="less")
  if (question$type %in% c("multiple_choice","matrix","ranking","allocation")) common <- c(common,
    stats::setNames("contains",switch(question$type,matrix="Any row has this answer",ranking="Includes this ranked option",allocation="Any allocation amount equals", "Includes this answer")))
  common
}

brohn_flow_option_value <- function(question, option) if (question$type == "ranking") option$id else option$value

brohn_flow_value_label <- function(value) {
  if (is.character(value)) return(paste0(brohn_json(value), " (text)"))
  if (is.logical(value)) return(paste(if (value) "true" else "false", "(boolean)"))
  paste(brohn_json(value), "(number)")
}

brohn_flow_condition <- function(question, operation, source = "typed", option_id = NULL, value_type = NULL, value = NULL, existing = NULL) {
  compatible <- operation %in% unname(brohn_flow_operators(question))
  brohn_require(compatible || !is.null(existing), "Choose an operation that matches this question's answer type.")
  result <- list(op=operation,question_id=question$id)
  if (operation == "answered") return(result)
  if (source == "option") {
    option <- brohn_find(question$options,option_id)
    brohn_require(!is.null(option), "Choose an existing answer option.")
    result$value <- brohn_flow_option_value(question,option)
  } else {
    brohn_require(identical(source,"typed") && value_type %in% c("number","text","boolean"), "Declare whether this comparison uses a number, text or boolean.")
    if (value_type == "number") {
      numeric <- suppressWarnings(as.numeric(value))
      brohn_require(brohn_number(numeric), "Enter a finite numeric comparison."); result$value <- numeric
    } else if (value_type == "boolean") {
      brohn_require(value %in% c("true","false"), "Choose true or false."); result$value <- identical(value,"true")
    } else {
      brohn_require(brohn_text(value,10000,TRUE), "Enter the exact comparison text."); result$value <- value
    }
  }
  brohn_validate_rule(result,question$id)
  if (!compatible) brohn_require(identical(brohn_hash(result),brohn_hash(existing)),
    "This saved operation does not match the answer type. Choose an appropriate comparison before changing it; the saved condition is preserved.")
  result
}

brohn_flow_summary <- function(rule, questions, maximum = 1200L) {
  describe <- function(node) {
    if (is.null(node)) return("Always show this question.")
    if (node$op %in% c("and","or")) return(paste0(if (node$op=="and") "ALL of (" else "ANY of (",paste(vapply(node$rules,describe,character(1)),collapse="; "),")"))
    if (node$op == "not") return(paste0("NOT (",describe(node$rule),")"))
    question <- brohn_find(questions,node$question_id)
    label <- if (is.null(question)) paste("Unavailable question",node$question_id) else substr(question$prompt,1,120)
    operation <- switch(node$op,answered="has an answer",equals="equals",not_equals="does not equal (when answered)",contains="includes",greater="is greater than",less="is less than")
    value <- if (node$op == "answered") "" else paste0(" ",brohn_flow_value_label(node$value))
    if (!is.null(question) && node$op != "answered") {
      matched <- Filter(function(o) identical(brohn_json(brohn_flow_option_value(question,o)),brohn_json(node$value)),question$options)
      if (length(matched)) value <- paste0(" ",substr(matched[[1]]$label,1,120)," [",brohn_flow_value_label(node$value),"]")
    }
    paste0(label," ",operation,value)
  }
  result <- describe(rule)
  if (nchar(result)>maximum) paste0(substr(result,1,maximum)," ...") else result
}

brohn_flow_set_question <- function(design, question_id, rule) {
  earlier <- brohn_flow_earlier(design,question_id)
  brohn_validate_rule(rule,brohn_ids(earlier)); brohn_flow_nodes(rule)
  index <- match(question_id,brohn_ids(design$questions)); design$questions[[index]]["show_if"] <- list(rule)
  brohn_validate_design(design); design
}
