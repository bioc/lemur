
#' Project new data onto the latent spaces of an existing lemur fit
#'
#' @param fit an `lemur_fit` object
#' @param data a matrix with observations in the columns and features in the rows.
#'   Or a `SummarizedExperiment` / `SingleCellExperiment` object. The features must
#'   match the features in `fit`.
#' @param col_data col_data an optional data frame with `ncol(data)` rows.
#' @param use_assay if `data` is a `SummarizedExperiment` / `SingleCellExperiment` object,
#'   which assay should be used.
#' @param design,alignment_design the design formulas or design matrices that are used
#'   to project the data on the correct latent subspace. Both default to the designs
#'   from the `fit` object.
#' @param return which data structure is returned.
#'
#'
#' @returns Either a matrix with the low-dimensional embeddings of the `data` or
#'   an object of class `lemur_fit` wrapping that embedding.
#'
#' @examples
#'
#' data(glioblastoma_example_data)
#'
#' subset1 <- glioblastoma_example_data[,1:2500]
#' subset2 <- glioblastoma_example_data[,2501:5000]
#'
#' fit <- lemur(subset1, design = ~ condition, n_emb = 5,
#'              test_fraction = 0, verbose = FALSE)
#'
#' # Returns a `lemur_fit` object with the projection of `subset2`
#' fit2 <- project_on_lemur_fit(fit, subset2, return = "lemur_fit")
#' fit2
#'
#'
#'
#' @export
project_on_lemur_fit <- function(fit, data, col_data = NULL, use_assay = "logcounts",
                                 design = fit$design, alignment_design = fit$alignment_design,
                                 return = c("matrix", "lemur_fit")){
  return <- match.arg(return)
  Y <- handle_data_parameter(data, on_disk = FALSE, assay = use_assay)
  col_data <- glmGamPoi:::get_col_data(data, col_data)

  xlevel <- attr(design, "xlevel") %default_to% attr(alignment_design, "xlevel")
  for(lvl in names(xlevel)){
    if(lvl %in% names(col_data)){
      col_data[[lvl]] <- factor(col_data[[lvl]], levels = xlevel[[lvl]])
    }else{
      stop("The column data does not contain the covariate ", lvl, ". This is a problem",
           "because it was used in the original design.")
    }
  }
  attr(design, "ignore_degeneracy") <- TRUE
  attr(alignment_design, "ignore_degeneracy") <- TRUE

  des <- handle_design_parameter(design, data, col_data)
  al_des <- handle_design_parameter(alignment_design, data, col_data)
  embedding <- project_on_lemur_fit_impl(Y, des$design_matrix, al_des$design_matrix,
                                         fit$coefficients, fit$linear_coefficients, fit$alignment_coefficients,
                                         fit$base_point)
  colnames(embedding) <- colnames(data)

  if(return == "matrix"){
    embedding
  }else if(return == "lemur_fit"){
    lemur_fit(data, col_data = col_data,
              row_data = if(is(data, "SummarizedExperiment")) rowData(data) else NULL,
              n_embedding = fit$n_embedding,
              design = des$design_formula, design_matrix = des$design_matrix,
              linear_coefficients = fit$linear_coefficients,
              base_point = fit$base_point,
              coefficients = fit$coefficients,
              embedding = embedding,
              alignment_coefficients = fit$alignment_coefficients,
              alignment_design = al_des$design_formula,
              alignment_design_matrix = al_des$design_matrix,
              use_assay = use_assay, is_test_data = rep(FALSE, ncol(embedding)),
              row_mask = metadata(fit)$row_mask)
  }
}

project_on_lemur_fit_impl <- function(Y, design_matrix, alignment_design_matrix, coefficients, linear_coefficients, alignment_coefficients, base_point){
  Y_clean <- Y - linear_coefficients %*% t(design_matrix)
  embedding <- project_data_on_diffemb(Y_clean, design = design_matrix, coefficients = coefficients, base_point = base_point)
  embedding <- apply_linear_transformation(embedding, alignment_coefficients, alignment_design_matrix)
  # TODO: subset to row_mask? And then potentially also remove the check in find_de_neighborhoods line 143.
  embedding
}

