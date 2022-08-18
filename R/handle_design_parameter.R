
handle_design_parameter <- function(design, data, col_data){
  n_samples <- ncol(data)

  ignore_degeneracy <- isTRUE(attr(design, "ignore_degeneracy"))

  # Handle the design parameter
  if(is.matrix(design)){
    model_matrix <- design
    design_formula <- NULL
  }else if((is.vector(design) || is.factor(design))){
    if(length(design) != n_samples){
      if(length(design) == 1 && design == 1){
        stop("The specified design vector length (", length(design), ") does not match ",
             "the number of samples: ", n_samples, "\n",
             "Did you maybe mean: `design = ~ 1`?")
      }else{
        stop("The specified design vector length (", length(design), ") does not match ",
             "the number of samples: ", n_samples)
      }
    }
    tmp <- glmGamPoi:::convert_chr_vec_to_model_matrix(design, reference_level)
    model_matrix <- tmp$model_matrix
    design_formula <- tmp$formula
    attr(design_formula, "constructed_from") <- "vector"
  }else if(inherits(design,"formula")){
    tmp <- convert_formula_to_model_matrix(design, col_data)
    model_matrix <- tmp$model_matrix
    design_formula <- tmp$formula
    attr(design_formula, "constructed_from") <- "formula"
  }else{
    stop(paste0("design argment of class ", class(design), " is not supported. Please ",
                "specify a `model_matrix`, a `character vector`, or a `formula`."))
  }

  if(nrow(model_matrix) != ncol(data)) stop("Number of rows in col_data does not match number of columns of data.")
  if(! is.null(rownames(model_matrix)) &&
     ! all(rownames(model_matrix) == as.character(seq_len(nrow(model_matrix)))) && # That's the default rownames
     ! is.null(colnames(data))){
    if(! all(rownames(model_matrix) == colnames(data))){
      if(setequal(rownames(model_matrix), colnames(data))){
        # Rearrange the rows to match the columns of data
        model_matrix <- model_matrix[colnames(data), ,drop=FALSE]
      }else{
        stop("The rownames of the model_matrix / col_data do not match the column names of data.")
      }
    }
  }

  if(any(matrixStats::rowAnyNAs(model_matrix))){
    stop("The design matrix contains 'NA's for sample ",
         paste0(head(which(DelayedMatrixStats::rowAnyNAs(model_matrix))), collapse = ", "),
         ". Please remove them before you call 'differential_embedding()'.")
  }

  if(ncol(model_matrix) >= n_samples && ! ignore_degeneracy){
    stop("The model_matrix has more columns (", ncol(model_matrix),
         ") than the there are samples in the data matrix (", n_samples, " columns).\n",
         "Too few replicates / too many coefficients to fit model.\n",
         "The head of the design matrix: \n", format_matrix(head(model_matrix, n = 3)), "\n",
         "The head of the data: \n", format_matrix(head(data[,seq_len(min(5, ncol(data))),drop=FALSE], n = 3)))
  }

  # Check rank of model_matrix
  qr_mm <- qr(model_matrix)
  if(qr_mm$rank < ncol(model_matrix) && n_samples > 0  && ! ignore_degeneracy){
    is_zero_column <- DelayedMatrixStats::colCounts(model_matrix, value = 0) == nrow(model_matrix)
    if(any(is_zero_column)){
      stop("The model matrix seems degenerate ('matrix_rank(model_matrix) < ncol(model_matrix)'). ",
           "Column ", paste0(head(which(is_zero_column), n=10), collapse = ", "), " contains only zeros. \n",
           "The head of the design matrix: \n", format_matrix(head(model_matrix, n = 3)))
    }else{
      stop("The model matrix seems degenerate ('matrix_rank(model_matrix) < ncol(model_matrix)'). ",
           "Some columns are perfectly collinear. Did you maybe include the same coefficient twice?\n",
           "The head of the design matrix: \n", format_matrix(head(model_matrix, n = 3)))
    }
  }

  rownames(model_matrix) <- colnames(data)
  validate_model_matrix(model_matrix, data)
  # model_matrix <- add_attr_if_intercept(model_matrix)
  list(model_matrix = model_matrix, design_formula = design_formula)
}



convert_formula_to_model_matrix <- function(formula, col_data){
  attr(col_data, "na.action") <- "na.pass"
  tryCatch({
    mf <- model.frame(formula, data = col_data, drop.unused.levels = TRUE)
    terms <- attr(mf, "terms")
    attr(terms, "xlevels") <- stats::.getXlevels(terms, mf)
    mm <- stats::model.matrix.default(terms, mf)
  }, error = function(e){
    # Try to extract text from error message
    match <- regmatches(e$message, regexec("object '(.+)' not found", e$message))[[1]]
    if(length(match) == 2){
      stop("Error while parsing the formula (", formula, ").\n",
           "Variable '", match[2], "' not found in col_data or global environment. Possible variables are:\n",
           paste0(colnames(col_data), collapse = ", "), call. = FALSE)
    }else{
      stop(e$message)
    }
  })

  # Otherwise every copy of the model stores the whole global environment!
  attr(terms, ".Environment") <- c()
  colnames(mm)[colnames(mm) == "(Intercept)"] <- "Intercept"
  list(formula = terms, model_matrix = mm)
}

validate_model_matrix <- function(matrix, data){
  stopifnot(is.matrix(matrix))
  stopifnot(nrow(matrix) == ncol(data))
}
