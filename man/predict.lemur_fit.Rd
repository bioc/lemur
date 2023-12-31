% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/predict.R
\name{predict.lemur_fit}
\alias{predict.lemur_fit}
\title{Predict values from \code{lemur_fit} object}
\usage{
\method{predict}{lemur_fit}(
  object,
  newdata = NULL,
  newdesign = NULL,
  newcondition = NULL,
  embedding = object$embedding,
  with_linear_model = TRUE,
  with_embedding = TRUE,
  with_alignment = TRUE,
  ...
)
}
\arguments{
\item{object}{an \code{lemur_fit} object}

\item{newdata}{a data.frame which passed to \code{\link{model.matrix}} with
\code{design} to make the \code{newdesign} matrix}

\item{newdesign}{a matrix with the covariates for which the output
is predicted. If \code{NULL}, the \code{object$design_matrix} is used. If
it is a vector it is repeated \code{ncol(embedding)} times to create
a design matrix with the same entry for each cell.}

\item{newcondition}{an unquoted expression with a call to \code{cond()} specifying
the covariates of the prediction. See the \code{contrast} argument in \link{test_de}
for more details. Note that combinations of multiple calls to \code{cond()} are
not allowed (e.g., \code{cond(a = 1) - cond(a = 2)}). If specified, \code{newdata}
and \code{newdesign} are ignored.}

\item{embedding}{the low-dimensional cell position for which the
output is predicted.}

\item{with_linear_model}{a boolean to indicate if the linear regression
offset is included in the prediction.}

\item{with_embedding}{a boolean to indicate if the embedding contributes
to the output.}

\item{with_alignment}{a boolean to indicate if the alignment effect
is removed from the output.}

\item{...}{additional parameters passed to \code{predict_impl}.}
}
\value{
A matrix with the same dimension \code{nrow(object) * nrow(newdesign)}.
}
\description{
Predict values from \code{lemur_fit} object
}
\examples{

data(glioblastoma_example_data)
fit <- lemur(glioblastoma_example_data, design = ~ patient_id + condition,
             n_emb = 5, verbose = FALSE)

pred <- predict(fit)

pred_ctrl <- predict(fit, newdesign = c(1, 0, 0, 0, 0, 0))
pred_trt <-  predict(fit, newdesign = c(1, 0, 0, 0, 0, 1))
# This is the same as the test_de result
fit <- test_de(fit, cond(condition = "panobinostat") - cond(condition = "ctrl"))
all.equal(SummarizedExperiment::assay(fit, "DE"), pred_trt - pred_ctrl,
          check.attributes = FALSE)

}
\seealso{
\code{\link[=residuals,lemur_fit-method]{residuals}}
}
