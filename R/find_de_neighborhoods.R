
#' @importFrom glmGamPoi vars
#'
#' @returns see [glmGamPoi::vars].
#'
#' @examples
#'   # `vars` quotes expressions (just like in dplyr)
#'   vars(condition, sample)
#'
#' @export
glmGamPoi::vars

#' Find differential expression neighborhoods
#'
#' @param fit the `lemur_fit` generated by `lemur()`
#' @param group_by If the `independent_matrix` is provided, `group_by` defines
#'   how the pseudobulks are formed.
#' @param contrast a specification which contrast to fit. This defaults to the
#'   `contrast` argument that was used for `test_de` and is stored in `fit$contrast`.
#' @param selection_procedure specify the algorithm that is used to select the
#'   neighborhoods for each gene. Broadly, `selection_procedure = "zscore"` is faster
#'   but less precise than `selection_procedure = "contrast"`.
#' @param directions a string to define the algorithm to select the direction onto
#'   which the cells are projected before searching for the neighborhood.
#'   `directions = "random"` produces denser neighborhoods, whereas `directions = "contrast"`
#'   has usually more power. \cr
#'   Alternatively, this can also be a matrix with one direction for each gene
#'   (i.e., a matrix of size `nrow(fit) * fit$n_embedding`).
#' @param min_neighborhood_size the minimum number of cells per neighborhood. Default: `50`.
#' @param de_mat the matrix with the differential expression values and is only relevant if
#'   `selection_procedure = "zscore"` or `directions = "random"`. Defaults
#'   to an assay called `"DE"` that is produced by `lemur::test_de()`.
#' @param test_data a `SummarizedExperiment` object or a named list of matrices. The
#'   data is used to test if the neighborhood inferred on the training data contain a
#'   reliable significant change. If `test_method` is `"glmGamPoi"` or `"edgeR"` a test
#'   using raw counts is conducted and two matching assays are needed: (1) the continuous
#'   assay (with `continuous_assay_name`) is projected onto the LEMUR fit to find the latent
#'   position of each cell and (2) the count assay (`count_assay_name`) is used for
#'   forming the pseudobulk. If `test_method == "limma"`, only the continuous assay is needed. \cr
#'   The arguments defaults to the test data split of when calling `lemur()`.
#' @param test_data_col_data additional column data for the `test_data` argument.
#' @param size_factor_method Set the procedure to calculate the size factor after pseudobulking. This argument
#'   is only relevant if `test_method` is `"glmGamPoi"` or `"edgeR"`. If `fit` is subsetted, using a
#'   vector with the sequencing depth per cell ensures reasonable results.
#'   Default: `NULL` which means that `colSums(assay(fit$test_data, count_assay_name))` is used.
#' @param test_method choice of test for the pseudobulked differential expression.
#'   [glmGamPoi](https://bioconductor.org/packages/glmGamPoi/) and
#'   [edgeR](https://bioconductor.org/packages/edgeR/) work on an count assay.
#'   [limma](http://bioconductor.org/packages/limma/) works on the continuous assay.
#' @param continuous_assay_name,count_assay_name the assay or list names of `independent_data`.
#' @param design,alignment_design the design to use for the fit. Default: `fit$design`
#' @param add_diff_in_diff a boolean to specify if the log-fold change (plus significance) of
#'   the DE in the neighborhood against the DE in the complement of the neighborhood is calculated.
#'   If `TRUE`, the result includes three additional columns starting with `"did_"` short for
#'   difference-in-difference. Default: `TRUE`.
#' @param make_neighborhoods_consistent Include cells from outside the neighborhood if they are
#'   at least 10 times in the k-nearest neighbors of the cells inside the neighborhood. Secondly,
#'   remove cells from the neighborhood which are less than 10 times in the k-nearest neighbors of the
#'   other cells in the neighborhood. Default `FALSE`
#' @param skip_confounded_neighborhoods Sometimes the inferred neighborhoods are not limited to
#'   a single cell state; this becomes problematic if the cells of the conditions compared in the contrast
#'   are unequally distributed between the cell states. Default: `FALSE`
#' @param verbose Should the method print information during the fitting. Default: `TRUE`.
#' @param control_parameters named list with additional parameters passed to underlying functions.
#'
#' @return a data frame with one entry per gene
#'   \describe{
#'      \item{`name`}{The gene name.}
#'      \item{`neighborhood`}{A list column where each element is a vector with the cell names included
#'      in that neighborhood.}
#'      \item{`n_cells`}{the number of cells in the neighborhood (`lengths(neighborhood)`).}
#'      \item{`sel_statistic`}{The statistic that is maximized by the `selection_procedure`.}
#'      \item{`pval`, `adj_pval`, `t_statistic`, `lfc`}{The p-value, Benjamini-Hochberg adjusted p-value (FDR), the
#'      t-statistic, and the log2 fold change of the differential expression test defined by `contrast` for the
#'      cells inside the neighborhood (calculated using `test_method`). Only present if `test_data` is not `NULL`.}
#'      \item{`did_pval`, `did_adj_pval`, `did_lfc`}{The measurement if the differential expression of the cells
#'      inside the neighborhood is significantly different from the differential expression of the cells outside
#'      the neighborhood. Only present if `add_diff_in_diff = TRUE`.}
#'   }
#'
#' @examples
#' data(glioblastoma_example_data)
#' fit <- lemur(glioblastoma_example_data, design = ~ patient_id + condition,
#'              n_emb = 5, verbose = FALSE)
#' # Optional alignment
#' # fit <- align_harmony(fit)
#' fit <- test_de(fit, contrast = cond(condition = "panobinostat") - cond(condition = "ctrl"))
#' nei <- find_de_neighborhoods(fit, group_by = vars(condition, patient_id))
#' head(nei)
#'
#' @export
find_de_neighborhoods <- function(fit,
                                  group_by,
                                  contrast = fit$contrast,
                                  selection_procedure = c("zscore", "contrast"),
                                  directions = c("random", "contrast", "axis_parallel"),
                                  min_neighborhood_size = 50,
                                  de_mat = SummarizedExperiment::assays(fit)[["DE"]],
                                  test_data = fit$test_data,
                                  test_data_col_data = NULL,
                                  test_method = c("glmGamPoi", "edgeR", "limma", "none"),
                                  continuous_assay_name = fit$use_assay,
                                  count_assay_name = "counts",
                                  size_factor_method = NULL,
                                  design = fit$design,
                                  alignment_design = fit$alignment_design,
                                  add_diff_in_diff = TRUE,
                                  make_neighborhoods_consistent = FALSE,
                                  skip_confounded_neighborhoods = FALSE,
                                  control_parameters = NULL,
                                  verbose = TRUE){
  stopifnot(is(fit, "lemur_fit"))
  test_method <- match.arg(test_method)
  skip_independent_test <- is.null(test_data) || test_method == "none"
  use_empty_test_projection <- is.null(test_data)
  use_existing_test_projection <- identical(test_data, fit$test_data)
  training_fit <- fit$training_data
  control_parameters <- control_parameters %default_to%
    list(select_directions_from_random_points.n_random_directions = 50,
         find_de_neighborhoods_with_contrast.ridge_penalty = 0.1,
         neighborhood_test.shrink = TRUE,
         make_neighborhoods_consistent.knn = 25, make_neighborhoods_consistent.cell_inclusion_threshold = 10,
         null_confounded_neighborhoods.normal_quantile = 0.99,
         merge_indices_columns = NA)

  test_data <- handle_test_data_parameter(fit, test_data, test_data_col_data, continuous_assay_name)
  if(nrow(fit) != nrow(test_data)){
    stop("The number of features in 'fit' and 'independent_data' differ.")
  }else{
    if(! is.null(rownames(fit)) && ! is.null(rownames(test_data)) &&
       any(rownames(fit) != rownames(test_data))){
      stop("The rownames differ between 'fit' and 'independent_data'.")
    }
  }
  merge_indices_columns <- isTRUE(control_parameters$merge_indices_columns) ||
    (is.na(control_parameters$merge_indices_columns) && identical(test_data, fit$test_data))

  if(use_empty_test_projection){
    projected_indep_data <- matrix(nrow = fit$n_embedding, ncol = 0)
  }else if(use_existing_test_projection){
    projected_indep_data <- fit$embedding[,fit$is_test_data,drop=FALSE]
  }else{
    if(! all(metadata(fit)$row_mask == seq_len(nrow(fit$base_point)))){
      stop("The 'fit' argument of 'find_de_neighborhoods' must not be subsetted.")
    }
    attr(design, "ignore_degeneracy") <- TRUE
    attr(alignment_design, "ignore_degeneracy") <- TRUE
    projected_indep_data <- project_on_lemur_fit(training_fit, data = test_data, use_assay = continuous_assay_name,
                                                 design = design, alignment_design = alignment_design, return = "matrix")
  }


  if(is.character(directions)){
    directions <- match.arg(directions)
    # There is one direction vector for each gene
    if(directions == "random"){
      if(is.null(de_mat)) stop("'directions = \"random\"' needs the predicted difference between two conditions. Please provide a valid 'de_mat'",
                               "argument or call 'fit <- test_de(fit, ...)'")
      stopifnot(all(dim(de_mat) == dim(fit)))
      dirs <- select_directions_from_random_points(control_parameters$select_directions_from_random_points.n_random_directions,
                                                   training_fit$embedding, de_mat[,!fit$is_test_data,drop=FALSE])
    }else if(directions == "contrast"){
      dirs <- select_directions_from_contrast(training_fit, {{contrast}})
    }else if(directions == "axis_parallel"){
      if(is.null(de_mat)) stop("'directions = \"axis_parallel\"' needs the predicted difference between two conditions. Please provide a valid 'de_mat'",
                               "argument or call 'fit <- test_de(fit, ...)'")
      stopifnot(all(dim(de_mat) == dim(fit)))
      dirs <- select_directions_from_axes(training_fit$embedding, de_mat[,!fit$is_test_data,drop=FALSE])
    }
  }else{
    stopifnot(is.matrix(directions))
    dirs <- directions
  }
  stopifnot(nrow(dirs) == nrow(fit) && ncol(dirs) == fit$n_embedding)

  if(is.character(selection_procedure)){
    selection_procedure <- match.arg(selection_procedure)
    if(verbose) message("Find optimal neighborhood using ", selection_procedure, ".")
    if(selection_procedure == "zscore"){
      if(is.null(de_mat)) stop("'selection_procedure = \"zscore\"' needs the predicted difference between two conditions. Please provide a valid 'de_mat'",
                               "argument or call 'fit <- test_de(fit, ...)'")
      stopifnot(all(dim(de_mat) == dim(fit)))
      de_regions <- find_de_neighborhoods_with_z_score(training_fit, dirs, de_mat[,!fit$is_test_data,drop=FALSE],
                                                       independent_embedding = projected_indep_data,
                                                       min_neighborhood_size = min_neighborhood_size, verbose = verbose)
    }else if(selection_procedure == "contrast"){
      de_regions <- find_de_neighborhoods_with_contrast(training_fit, dirs, group_by = {{group_by}}, contrast = {{contrast}},
                                                        use_assay = continuous_assay_name, independent_embedding = projected_indep_data,
                                                        min_neighborhood_size = min_neighborhood_size,
                                                        ridge_penalty = control_parameters$find_de_neighborhoods_with_contrast.ridge_penalty,
                                                        verbose = verbose)
    }else if(selection_procedure == "likelihood"){
      # Implement one of Wolfgang's suggestions for the selection procedure
      # de_regions <- find_de_neighborhoods_with_likelihood_ratio(training_fit, dirs, de_mat, include_complement = include_complement)
    }
  }else{
    stopifnot(is.data.frame(selection_procedure))
    stopifnot(c("name", "indices", "independent_indices", "sel_statistic") %in% colnames(selection_procedure))
    de_regions <- selection_procedure
  }

  if(skip_independent_test){
    colnames <- c("name", "indices", "n_cells", "sel_statistic")
  }else{
    if(verbose) message("Validate neighborhoods using test data")
    if(! is.null(rownames(fit)) && is.null(rownames(test_data))){
      rownames(test_data) <- rownames(fit)
    }
    if(any(rownames(fit) != rownames(test_data))){
      stop("The rownames of fit and counts don't match.")
    }
    if(rlang::quo_is_null(rlang::enquo(contrast))){
      stop("The contrast argument is 'NULL'. Please specify.")
    }
    tryCatch({
      if(inherits(contrast, "contrast_relation")){
        contrast <- evaluate_contrast_tree(contrast, contrast, \(x, y) x)
      }
    }, error = function(e){
      # Do nothing. The 'contrast' is probably an unquoted expression
    })

    if(make_neighborhoods_consistent){
      # Add cells which neighbor more than 10 cells in the neighborhood,
      # remove cells which have less than 10 neighbors in the neighborhood.
      de_regions[["independent_indices"]] <- make_neighborhoods_consistent(projected_indep_data, de_regions[["independent_indices"]], {{contrast}},
                                                                           design = fit$design, col_data = colData(test_data),
                                                                           knn = control_parameters$make_neighborhoods_consistent.knn,
                                                                           cell_inclusion_threshold = control_parameters$make_neighborhoods_consistent.cell_inclusion_threshold,
                                                                           verbose = verbose)
    }
    if(skip_confounded_neighborhoods){
      # Check if neighborhood is balanced between the conditions
      de_regions[["independent_indices"]] <- null_confounded_neighborhoods(projected_indep_data, de_regions[["independent_indices"]], {{contrast}},
                                                                           design = fit$design, col_data = colData(test_data),
                                                                           normal_quantile = control_parameters$null_confounded_neighborhoods.normal_quantile,
                                                                           verbose = verbose)
    }

    if(test_method != "limma"){
      if(! count_assay_name %in% assayNames(test_data)){
        stop("Trying to execute count-based differential expression analysis on the test data because 'test_method=\"", test_method, "\"'. However, ",
          "'count_assay_name=\"", count_assay_name,  "\"' is not an assay (",  paste0(assayNames(test_data), collapse = ", "),
             ") of the 'independent_data' object.")
      }
      if(verbose & ! is.numeric(size_factor_method) & length(metadata(fit)[["row_mask"]]) / nrow(fit$base_point) < 0.1){
        warning("The fit object was subset to less than 10% of the genes. This will make the size factor estimation unreliable. ",
                "Consider setting 'size_factor_method' to a vector with the appropriate sequencing depth per cell.")
      }

      colnames <- c("name", "indices", "n_cells", "sel_statistic", "pval", "adj_pval", "f_statistic", "df1", "df2", "lfc",
                    if(add_diff_in_diff) c("did_pval", "did_adj_pval", "did_lfc"))
      de_regions <- neighborhood_count_test(de_regions, counts = assay(test_data, count_assay_name), group_by = group_by, contrast = {{contrast}},
                              design = design, col_data = colData(test_data), shrink = control_parameters$neighborhood_test.shrink,
                              size_factor_method = size_factor_method, method = test_method, de_region_index_name = "independent_indices",
                              add_diff_in_diff = add_diff_in_diff, verbose = verbose)
    }else{
      colnames <- c("name", "indices", "n_cells", "sel_statistic", "pval", "adj_pval", "t_statistic", "lfc",
                    if(add_diff_in_diff) c("did_pval", "did_adj_pval", "did_lfc"))
      de_regions <- neighborhood_normal_test(de_regions, values = assay(test_data, continuous_assay_name), group_by = group_by, contrast = {{contrast}},
                                             design = design, col_data = colData(test_data), shrink = control_parameters$neighborhood_test.shrink,
                                             de_region_index_name = "independent_indices", add_diff_in_diff = add_diff_in_diff, verbose = verbose)
    }
  }

  if(merge_indices_columns){
    # Merge columns
    test_idx <- which(fit$is_test_data)
    train_idx <- which(!fit$is_test_data)
    skipped <- attr(de_regions[["independent_indices"]], "is_neighborhood_confounded")
    if(is.null(skipped)) skipped <- rep(FALSE, nrow(de_regions))
    de_regions$indices <- lapply(seq_len(nrow(de_regions)), \(row){
      if(skipped[row]){
        integer(0L)
      }else{
        c(train_idx[de_regions$indices[[row]]], test_idx[de_regions$independent_indices[[row]]])
      }
    })
    de_regions$independent_indices <- NULL
  }else{
    colnames <- c(colnames[1:3], "independent_indices", colnames[-(1:3)])
  }
  de_regions$n_cells <- lengths(de_regions$indices)
  de_regions$pval[de_regions$n_cells < min_neighborhood_size] <- NA_real_
  # Recalculate FDR, because there can be many skipped neighborhoods
  de_regions$adj_pval <- p.adjust(de_regions$pval, method = "BH")

  if("indices" %in% colnames){
    names <- if(merge_indices_columns) colnames(fit)
    else colnames(fit$training_data)
    de_regions[["neighborhood"]] <- if(! is.null(names)){
      if(length(names) != length(unique(names))) warning("`colnames(fit)` are not unique.")
      I(lapply(de_regions[["indices"]], \(idx) names[idx]))
    }else{
      de_regions[["indices"]]
    }
    colnames[colnames == "indices"] <- "neighborhood"
  }

  if("independent_indices" %in% colnames){
    names <- colnames(test_data)
    de_regions[["neighborhood_test_data"]] <- if(! is.null(names)){
      if(length(names) != length(unique(names))) warning("`colnames(test_data)` are not unique.")
      I(lapply(de_regions[["independent_indices"]], \(idx) names[idx]))
    }else{
      de_regions[["independent_indices"]]
    }
    colnames[colnames == "independent_indices"] <- "neighborhood_test_data"
    colnames[colnames == "neighborhood"] <- "neighborhood_training_data"
    names(de_regions)[names(de_regions) == "neighborhood"]  <- "neighborhood_training_data"
  }

  de_regions[colnames]
}

select_directions_from_axes <- function(embedding, de_mat){
  if(is.null(de_mat)){
    stop("'de_mat' is NULL. Please first call 'lemur::test_de()' to calculate the differential expression matrix.")
  }
  dirs <- diag(nrow = nrow(embedding))
  correlation <- cor(t(embedding), t(de_mat))
  best_proj <- vapply(seq_len(ncol(correlation)), \(idx) which.max(abs(correlation[,idx])), FUN.VALUE = integer(1L))
  dirs[best_proj,,drop=FALSE]
}

select_directions_from_random_points <- function(n_random_directions, embedding, de_mat){
  if(is.null(de_mat)){
    stop("'de_mat' is NULL. Please first call 'lemur::test_de()' to calculate the differential expression matrix.")
  }
  n_cells <- ncol(embedding)
  point_pairs <- matrix(sample.int(n_cells, 2 * n_random_directions, replace = TRUE), nrow = 2)
  # Remove point_paris which are identical
  if(any(point_pairs[1,] == point_pairs[2,])){
    problem <- point_pairs[1,] == point_pairs[2,]
    point_pairs[1,problem] <- (point_pairs[2,problem] %% n_cells) + 1
  }
  dirs <- lapply(seq_len(n_random_directions), \(idx){
    sel <- point_pairs[,idx]
    vec <- embedding[,sel[1]] - embedding[,sel[2]]
    vec / sqrt(sum(vec^2))
  })
  proj <- do.call(rbind, lapply(dirs, \(dir) c(coef(lm.fit(x = matrix(dir, ncol = 1), embedding)))))

  correlation <- cor(t(proj), t(de_mat))
  best_proj <- vapply(seq_len(ncol(correlation)), \(idx) which.max(abs(correlation[,idx])), FUN.VALUE = integer(1L))
  do.call(rbind, dirs[best_proj])
}

select_directions_from_contrast <- function(fit, contrast){
  cntrst <- parse_contrast({{contrast}}, formula = fit$design)
  dirs <- evaluate_contrast_tree(cntrst, cntrst, \(x, .){
    grassmann_map(sum_tangent_vectors(fit$coefficients, x), fit$base_point)
  })
  # Subset to available genes
  dirs <- dirs[metadata(fit)[["row_mask"]],,drop=FALSE]
  # Make each row unit length
  t(apply(dirs, 1, \(row) row / sqrt(sum(row^2))))
}

select_directions_from_canonical_correlation <- function(embedding, de_mat){
  if(is.null(de_mat)){
    stop("'de_mat' is NULL. Please first call 'lemur::test_de()' to calculate the differential expression matrix.")
  }
  stop("Not yet implemented")
}


find_de_neighborhoods_with_z_score <- function(fit, dirs, de_mat, independent_embedding = NULL,
                                               min_neighborhood_size = 50, verbose = TRUE){
  n_genes <- nrow(fit)
  n_cells <- ncol(fit)
  stopifnot(ncol(fit) == ncol(de_mat))
  stopifnot(nrow(fit) == nrow(de_mat))
  show_progress_bar <- verbose && interactive()
  proj <- dirs %*% fit$embedding
  if(is.null(independent_embedding)){
    independent_embedding <- matrix(nrow = fit$n_embedding, ncol = 0)
  }
  indep_proj <- dirs %*% independent_embedding

  if(show_progress_bar){
    progress_bar <- txtProgressBar(min = 0, max = n_genes, style = 3)
  }
  result <- do.call(rbind, lapply(seq_len(n_genes), \(gene_idx){
    if(show_progress_bar && gene_idx %% 10 == 0){
      setTxtProgressBar(progress_bar, value = gene_idx)
    }
    pr <- proj[gene_idx,]
    ipr <- indep_proj[gene_idx,]
    order_pr <- order(pr)
    max_idx <- cumz_which_abs_max(de_mat[gene_idx,order_pr], min_neighborhood_size = min(n_cells, min_neighborhood_size))
    rev_max_idx <- cumz_which_abs_max(rev(de_mat[gene_idx,order_pr]), min_neighborhood_size = min(n_cells, min_neighborhood_size))
    if(abs(max_idx$max) > abs(rev_max_idx$max)){
      data.frame(indices = I(list(unname(which(pr <= pr[order_pr][max_idx$idx])))),
                 independent_indices = I(list(unname(which(ipr <= pr[order_pr][max_idx$idx])))),
                 sel_statistic = max_idx$max)
    }else{
      data.frame(indices = I(list(unname(which(pr >= rev(pr[order_pr])[rev_max_idx$idx])))),
                 independent_indices = I(list(unname(which(ipr >= rev(pr[order_pr])[rev_max_idx$idx])))),
                 sel_statistic = rev_max_idx$max)
    }
  }))
  if(show_progress_bar){
    close(progress_bar)
  }
  result$name <- rownames(fit)
  if(is.null(result$name)){
    result$name <- paste0("feature_", seq_len(nrow(fit)))
  }

  result
}

find_de_neighborhoods_with_contrast <- function(fit, dirs, group_by, contrast, use_assay = fit$use_assay, independent_embedding = NULL,
                                                ridge_penalty = 0.1, min_neighborhood_size = 50, verbose = TRUE){
  n_genes <- nrow(fit)
  n_cells <- ncol(fit)
  cntrst <- parse_contrast({{contrast}}, formula = fit$design, simplify = TRUE)
  show_progress_bar <- verbose && interactive()


  # Prepare values
  Y <- assay(fit, use_assay)
  if(rlang::quo_is_null(rlang::enquo(group_by))){
    stop("The 'group_by' argument is NULL. Please provide the names from the column data should be used for aggregating the data.\n",
         "For example, 'group_by = vars(", paste0(head(colnames(fit$colData), n = 2), collapse = ","), ")'")
  }
  group <-  vctrs::vec_group_id(as.data.frame(lapply(group_by, rlang::eval_tidy, data = as.data.frame(fit$colData))))
  design_mat <- fit$design_matrix
  proj <- dirs %*% fit$embedding
  if(is.null(independent_embedding)){
    independent_embedding <- matrix(nrow = fit$n_embedding, ncol = 0)
  }
  indep_proj <- dirs %*% independent_embedding

  if(show_progress_bar){
    progress_bar <- txtProgressBar(min = 0, max = n_genes, style = 3)
  }
  result <- do.call(rbind, lapply(seq_len(n_genes), \(gene_idx){
    if(show_progress_bar && gene_idx %% 10 == 0){
      setTxtProgressBar(progress_bar, value = gene_idx)
    }
    pr <- proj[gene_idx,]
    ipr <- indep_proj[gene_idx,]
    order_pr <- order(pr)
    max_idx <- cum_brls_which_abs_max(Y[gene_idx, order_pr], design_mat[order_pr,], group = group[order_pr],
                                      contrast = cntrst, penalty = ridge_penalty, min_neighborhood_size = min(n_cells, min_neighborhood_size))
    rev_max_idx <- cum_brls_which_abs_max(Y[gene_idx, rev(order_pr)], design_mat[rev(order_pr),], group = group[rev(order_pr)],
                                          contrast = cntrst, penalty = ridge_penalty, min_neighborhood_size = min(n_cells, min_neighborhood_size))
    if(abs(max_idx$max) > abs(rev_max_idx$max)){
      # Add small number because equality test is unreliable for floats
      thres <- pr[order_pr][max_idx$idx] + 1e-12
      data.frame(indices = I(list(unname(which(pr <= thres)))),
                 independent_indices = I(list(unname(which(ipr <= thres)))),
                 sel_statistic = max_idx$max)
    }else{
      thres <- rev(pr[order_pr])[rev_max_idx$idx] - 1e-12
      data.frame(indices = I(list(unname(which(pr >= thres)))),
                 independent_indices = I(list(unname(which(ipr >= thres)))),
                 sel_statistic = rev_max_idx$max)
    }
  }))
  if(show_progress_bar){
    close(progress_bar)
  }
  result$name <- rownames(fit)
  if(is.null(result$name)){
    result$name <- paste0("feature_", seq_len(nrow(fit)))
  }

  result
}



neighborhood_count_test <- function(de_regions, counts, group_by, contrast, design, col_data,
                                    shrink = TRUE, size_factor_method = NULL, method = c("glmGamPoi", "edgeR"),
                                    de_region_index_name = "indices", add_diff_in_diff = TRUE, verbose = TRUE){
  method <- match.arg(method)
  mask <- matrix(0, nrow = nrow(de_regions),  ncol = ncol(counts))
  indices <- de_regions[[de_region_index_name]]
  for(idx in seq_len(nrow(de_regions))){
    mask[idx,indices[[idx]]] <- 1
  }

  if(is.null(rownames(counts))){
    rownames(counts) <- paste0("feature_", seq_len(nrow(counts)))
  }
  masked_counts <- counts[de_regions$name,,drop=FALSE] * mask

  masked_sce <- SingleCellExperiment::SingleCellExperiment(list(masked_counts = masked_counts, counts = counts[de_regions$name,,drop=FALSE]), colData = col_data)
  if(verbose) message("Form pseudobulk (summing counts)")
  region_psce <- glmGamPoi::pseudobulk(masked_sce, group_by = {{group_by}},
                                       aggregation_functions = list("masked_counts" = "rowSums2", "counts" = "rowSums2"),
                                       verbose = FALSE)
  if(verbose) message("Calculate size factors for each gene")
  size_factor_matrix <- pseudobulk_size_factors_for_neighborhoods(counts, mask = mask, col_data = col_data,
                                                        group_by = {{group_by}}, method = size_factor_method, verbose = verbose)
  size_factor_matrix <- size_factor_matrix[, colnames(region_psce)]  # The column order differs

  if(method == "glmGamPoi"){
    if(verbose) message("Fit glmGamPoi model on pseudobulk data")
    glm_regions <- glmGamPoi::glm_gp(region_psce, design = design, use_assay = "masked_counts", verbose = FALSE,
                                     offset = log(size_factor_matrix + 1e-10),
                                     size_factors = FALSE, overdispersion = TRUE, overdispersion_shrinkage = shrink)
    de_res <- glmGamPoi::test_de(glm_regions, contrast = {{contrast}})
  }else if(method == "edgeR"){
    if(! requireNamespace("edgeR", quietly = TRUE)){
      stop("to use 'find_de_neighborhoods' in combination with 'edgeR', you need to separately install edgeR.\n",
           "BiocManager::install('edgeR')")
    }
    if(verbose) message("Fit edgeR model on pseudobulk data")
    glm_regions <- edger_fit(assay(region_psce, "masked_counts"), design = design, offset = log(size_factor_matrix + 1e-10),
                           col_data = SummarizedExperiment::colData(region_psce))
    de_res <- edger_test_de(glm_regions, {{contrast}}, design)
  }

  if(add_diff_in_diff){
    if(verbose) message("Fit diff-in-diff effect")
    mm <- if(method == "glmGamPoi") glm_regions$model_matrix else glm_regions$design
    mat <- assay(region_psce, "masked_counts")
    complement_mat <- assay(region_psce, "counts") - assay(region_psce, "masked_counts")
    cntrst <- parse_contrast({{contrast}}, design, simplify = TRUE)

    comb_mat <- unname(cbind(mat, complement_mat))
    zero_mat <- array(0, dim = dim(mm))
    # Fit the model separately to the neighborhood and its complement
    comb_design_mat <- unname(rbind(cbind(mm, zero_mat), cbind(zero_mat, mm)))
    mod_col_data <- cbind(rbind(col_data, col_data), ..did_indicator = rep(c(0, 1), each = nrow(col_data)))
    mod_size_factor_matrix <- pseudobulk_size_factors_for_neighborhoods(cbind(counts, counts), mask = cbind(mask, 1-mask),
                                                                        col_data = mod_col_data, group_by = c({{group_by}}, vars(..did_indicator)),
                                                                        method = size_factor_method, verbose = verbose)
    if(method == "glmGamPoi"){
      did_fit <- glmGamPoi::glm_gp(comb_mat, design = comb_design_mat, verbose = FALSE,
                                   offset = log(mod_size_factor_matrix + 1e-10),
                                   size_factors = FALSE, overdispersion = TRUE, overdispersion_shrinkage = shrink)
      did_res <- glmGamPoi::test_de(did_fit, contrast = c(-cntrst, cntrst))
    }else if(method == "edgeR"){
      did_fit <- edger_fit(comb_mat, design = comb_design_mat, offset = log(mod_size_factor_matrix + 1e-10))
      did_res <- edger_test_de(did_fit,  c(-cntrst, cntrst))
    }
    colnames(did_res) <- paste0("did_", colnames(did_res))

    cbind(de_regions, de_res[,-1], did_res[,c("did_pval", "did_adj_pval", "did_lfc")])
  }else{
    cbind(de_regions, de_res[,-1])
  }

}


neighborhood_normal_test <- function(de_regions, values, group_by, contrast, design, col_data,
                                     shrink = TRUE, de_region_index_name = "indices", add_diff_in_diff = TRUE, verbose = TRUE){
  if(is.null(de_regions$name)){
    stop("The de_region data frame must contain a column called 'name'.")
  }

  mask <- matrix(0, nrow = nrow(de_regions),  ncol = ncol(values))
  indices <- de_regions[[de_region_index_name]]
  for(idx in seq_len(nrow(de_regions))){
    mask[idx,indices[[idx]]] <- 1
  }
  mask <- as_dgTMatrix(mask)


  if(is.null(rownames(values))){
    if(nrow(values) == nrow(de_regions)){
      rownames(values) <- de_regions$name
    }else{
      stop("'values' does not have rownames and its number of rows does not match the number of rows ",
           "in 'de_regions'. Thus the matching between 'de_regions' and 'values' is ambiguous.")
    }
  }
  masked_values <- values[de_regions$name,,drop=FALSE] * mask
  if(verbose) message("Form pseudobulk (averaging values)")
  groups <- lapply(group_by, rlang::eval_tidy, data = as.data.frame(col_data))
  if(is.null(groups)){
    stop("'group_by' must not be 'NULL'.")
  }
  names(groups) <- vapply(group_by, rlang::as_label, character(1L))
  split_res <- vctrs::vec_group_loc(as.data.frame(groups))
  group_split <- split_res$loc
  names(group_split) <- do.call(paste, c(split_res$key, sep = "."))

  M <- aggregate_matrix(masked_values, group_split, MatrixGenerics::rowSums2) /
    aggregate_matrix(mask, group_split, MatrixGenerics::rowSums2)

  if(verbose) message("Fit limma model")
  lm_fit <- limma_fit(M, design, col_data = split_res$key)
  de_res <- limma_test_de(lm_fit, {{contrast}}, design, values = M, shrink = shrink)

  if(add_diff_in_diff){
    mm <- lm_fit$design
    inverse_mask <- (1 - mask)
    compl_masked_values <- values[de_regions$name,,drop=FALSE] * inverse_mask
    CM <- aggregate_matrix(compl_masked_values, group_split, MatrixGenerics::rowSums2) /
      aggregate_matrix(inverse_mask, group_split, MatrixGenerics::rowSums2)
    cntrst <- parse_contrast({{contrast}}, design, simplify = TRUE)

    comb_mat <- unname(cbind(M, CM))
    zero_mat <- array(0, dim = dim(mm))
    # Fit the model separately to the neighborhood and its complement
    comb_design_mat <- unname(rbind(cbind(mm, zero_mat), cbind(zero_mat, mm)))
    if(verbose) message("Fit diff-in-diff effect")
    did_fit <- limma_fit(comb_mat, comb_design_mat)
    did_res <- limma_test_de(did_fit, c(-cntrst, cntrst), design = NULL, values = comb_mat, shrink = shrink)
    colnames(did_res) <- paste0("did_", colnames(did_res))

    cbind(de_regions, de_res[,-1], did_res[,c("did_pval", "did_adj_pval", "did_lfc")])
  }else{
    cbind(de_regions, de_res[,-1])
  }

}




pseudobulk_size_factors_for_neighborhoods <- function(counts, mask, col_data, group_by,
                                                      method = c("normed_sum", "ratio"), verbose = TRUE){
  if(is.numeric(method)){
    cell_size_factors <- method
    method <- "cell_size_factors_provided"
  }else if(is.null(method)){
    method <- "normed_sum"
  }else{
    method <- match.arg(method)
  }

  # Evaluate group_by argument
  groups <- lapply(group_by, rlang::eval_tidy, data = as.data.frame(col_data))
  split_res <- vctrs::vec_group_loc(as.data.frame(groups))
  group_split <- split_res$loc

  if(method == "cell_size_factors_provided"){
    masked_size_factors <- t(t(mask) * cell_size_factors)
    size_factors <- aggregate_matrix(masked_size_factors, group_split, MatrixGenerics::rowSums2)
  }else if(method == "normed_sum"){
    cell_col_sums <- MatrixGenerics::colSums2(counts)
    masked_size_factors <- t(t(mask) * cell_col_sums)
    size_factors <- aggregate_matrix(masked_size_factors, group_split, MatrixGenerics::rowSums2)
  }else if(method == "ratio"){
    n_genes <- nrow(mask)
    show_progress_bar <- verbose && interactive()
    if(show_progress_bar){
      progress_bar <- txtProgressBar(min = 0, max = n_genes, style = 3)
    }

    cell_col_sums <- MatrixGenerics::colSums2(counts)
    # 200 genes are often enough to get a good estimate and it speeds up the calculation by a lot!
    top_expressed_genes <- counts[order(-MatrixGenerics::rowMeans2(counts))[seq_len(min(nrow(counts), 200))], ,drop = FALSE]

    size_factors <- mply_dbl(seq_len(n_genes), \(idx){
      if(show_progress_bar && idx %% 10 == 0){
        setTxtProgressBar(progress_bar, value = idx)
      }
      mask_row <- mask[idx, ]
      absent_sample <- vapply(group_split, \(sel) sum(mask_row[sel]) == 0, FUN.VALUE = logical(1L))
      sf <- rep(0, length(group_split))
      if(all(absent_sample)){
        sf
      }else{
        Y <- aggregate_matrix(top_expressed_genes, group_split[!absent_sample], MatrixGenerics::rowSums2, col_sel = mask_row == 1)
        log_geo_means <- DelayedMatrixStats::rowMeans2(log(Y))
        sf[! absent_sample] <- apply(Y, 2, function(cnts) {
          exp(median((log(cnts) - log_geo_means)[is.finite(log_geo_means) & cnts > 0]))
        })
        if(any(! is.finite(sf))){
          # Something went wrong (maybe the data was too sparse), fall back to "normed_sum"
          drop(aggregate_matrix(matrix(cell_col_sums * mask_row, nrow = 1), group_split, MatrixGenerics::rowSums2))
        }else{
          sf
        }
      }
    }, ncol = length(group_split))
    if(show_progress_bar){
      close(progress_bar)
    }
  }else{
    stop("Illegal method argument")
  }

  sf_center <- rowMeans(size_factors)
  size_factors <- size_factors / pmax(1e-5, sf_center)
  colnames(size_factors) <- do.call(paste, c(split_res$key, sep = "."))
  size_factors
}


make_neighborhoods_consistent <- function(embedding, indices, contrast, design, col_data,
                                          knn = 25, cell_inclusion_threshold = 10, verbose = TRUE){

  if(verbose) message("Make neighborhoods consistent by adding connected and removing isolated cells")
  n_genes <- length(indices)
  stopifnot(cell_inclusion_threshold >= 0)
  show_progress_bar <- verbose && interactive()

  cntrst <- matrix(parse_contrast({{contrast}}, formula = design, simplify = TRUE), ncol = 1)
  design_matrix <- convert_formula_to_design_matrix(design, col_data)$design_matrix
  condition <- kmeans(c(design_matrix %*% cntrst), centers = 2)$cluster

  knn_mat <- BiocNeighbors::findAnnoy(t(embedding), k = knn, get.distance = FALSE)$index

  if(show_progress_bar){
    progress_bar <- txtProgressBar(min = 0, max = n_genes, style = 3)
  }

  cell_freq <- lapply(seq_along(indices), \(gene_idx){
    if(show_progress_bar && gene_idx %% 10 == 0){
      setTxtProgressBar(progress_bar, value = gene_idx)
    }
    count_neighbors_fast(knn_mat, indices[[gene_idx]])
  })
  if(show_progress_bar){
    close(progress_bar)
  }

  lapply(seq_along(cell_freq), \(i){
    which(cell_freq[[i]] >= cell_inclusion_threshold)
  })
}

null_confounded_neighborhoods <- function(embedding, indices, contrast, design, col_data, normal_quantile = 0.99, verbose = TRUE){

  neighborhood_sizes <- lengths(indices)
  large_neighborhood <- neighborhood_sizes >= median(neighborhood_sizes)

  if(diff(range(neighborhood_sizes[large_neighborhood])) < 10){
    # Do nothing
  }else{
    cntrst <-  matrix(parse_contrast({{contrast}}, formula = design, simplify = TRUE), ncol = 1)
    design_matrix <- convert_formula_to_design_matrix(design, col_data)$design_matrix
    condition <- kmeans(c(design_matrix %*% cntrst), centers = 2)$cluster

    means_cond1 <- aggregate_matrix(embedding, indices, MatrixGenerics::rowMeans2, col_sel = condition == 1)
    means_cond2 <- aggregate_matrix(embedding, indices, MatrixGenerics::rowMeans2, col_sel = condition == 2)

    dist <- sqrt(matrixStats::colSums2((means_cond1 - means_cond2)^2))

    # Fit a straight line to the larger half (the lower bits are very unreliable)
    dist_fit <- lm(dist ~ neighborhood_sizes, subset = large_neighborhood)
    limit <- max(sd(residuals(dist_fit)), 1e-5) * qnorm(p = normal_quantile)
    all_residuals <- dist - predict(dist_fit, newdata = data.frame(neighborhood_sizes = neighborhood_sizes))
    skip <- all_residuals > limit
    skip[is.na(skip)] <- TRUE # NA's occurs if a condition is completely empty

    if(sum(skip > 0) && verbose) message("Skipping ", sum(skip > 0), " neighborhoods which contain unbalanced cell states")

    indices[skip] <- lapply(seq_len(sum(skip)), \(i) integer(0L))
    attr(indices, "is_neighborhood_confounded") <- skip
  }
  indices
}
