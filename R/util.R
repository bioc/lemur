randn <- function(n, m, ...){
  matrix(rnorm(n * m, ...), nrow = n, ncol = m)
}

skew <- function(M){
  0.5 * (M - t(M))
}


#' Iterating function that returns a matrix
#'
#' The length of `x` determines the number of rows. The length of
#' `FUN(x[i])` determines the number of columns. Must match `ncol`.
#'
#' @keywords internal
mply_dbl <- function(x, FUN, ncol=1, ...){
  if(!is.matrix(x)){
    res <- vapply(x, FUN, FUN.VALUE=rep(0.0, times=ncol), ...)
  }else{
    res <- apply(x, 1, FUN, ...) * 1.0
    if(nrow(x) > 0 && length(res) == 0){
      # Empty result, make matrix
      res <- matrix(numeric(0),nrow=0, ncol=nrow(x))
    }else if(nrow(x) == 0){
      res <- matrix(numeric(0), nrow=ncol, ncol=0)
    }
    if((ncol == 1 && ! is.vector(res)) || (ncol > 1 && nrow(res) != ncol)){
      stop(paste0("values must be length ", ncol,
                  ", but result is length ", nrow(res)))
    }
  }

  if(ncol == 1){
    as.matrix(res, nrow=length(res), ncol=1)
  }else{
    t(res)
  }
}

#' @describeIn mply_dbl flexible version that automatically infers the number
#'   of columns
msply_dbl <- function(x, FUN, ...){
  if(is.vector(x)){
    res <- sapply(x, FUN, ...)
  }else{
    res <- apply(x, 1, FUN, ...)
  }

  if(is.list(res)){
    if(all(vapply(res, function(x) is.numeric(x) && length(x) == 0, FUN.VALUE = FALSE))){
      res <- matrix(numeric(0),nrow=0, ncol=length(res))
    }else{
      stop("Couldn't simplify result to a matrix")
    }
  }
  if(is.matrix(x) && length(res) == 0){
    # Empty result, make matrix
    res <- matrix(numeric(0),nrow=0, ncol=nrow(x))
  }

  if(is.numeric(res)){
    # Do nothing
  }else if(is.logical(res)){
    res <- res * 1.0
  }else{
    stop(paste0("Result is of type ", typeof(res), ". Cannot convert to numeric."))
  }

  if(is.matrix(res)){
    t(res)
  }else{
    as.matrix(res, nrow=length(res))
  }
}



#'
#' @describeIn mply_dbl Each list element becomes a row in a matrix
stack_rows <- function(x){
  stopifnot(is.list(x))
  do.call(rbind, x)
}

#'
#' @describeIn mply_dbl Each list element becomes a row in a matrix
stack_cols <- function(x){
  stopifnot(is.list(x))
  do.call(cbind, x)
}

#' Make a cube from a list of matrices
#'
#'
stack_slice <- function(x){
  stopifnot(is.list(x))
  x <- lapply(x, as.matrix)
  if(length(x) == 0){
    array(dim = c(0, 0, 0))
  }else{
    dim <- dim(x[[1]])
    res <- array(NA, dim = c(dim, length(x)))
    for(idx in seq_along(x)){
      elem <- x[[idx]]
      if(nrow(elem) != dim[1] || ncol(elem) != dim[2]){
        stop("Size doesn't match")
      }
      res[,,idx] <- elem
    }
    res
  }
}

#' @describeIn stack_slice Make a list of matrices from a cube
#'
destack_slice <- function(x){
  stopifnot(is.array(x))
  stopifnot(length(dim(x)) == 3)
  lapply(seq_len(dim(x)[3]), \(idx) x[,,idx])
}


duplicate_rows <- function(m, times, each){
  if(missing(times) && missing(each)){
    do.call(rbind, list(m))
  }else if(! missing(times)){
    do.call(rbind, lapply(seq_len(times), \(i) m))
  }else if(! missing(each)){
    matrix(rep(m, each = each), nrow = each  * nrow(m), ncol = ncol(m))
  }else{
    stop("Specify either 'times' or 'each'")
  }
}

duplicate_cols <- function(m, times, each){
  t(duplicate_rows(t(m), times = times, each = each))
}


sum_third_dimension <- einsum::einsum_generator("ijk->ij")