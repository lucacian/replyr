
# Contributed by John Mount jmount@win-vector.com , ownership assigned to Win-Vector LLC.
# Win-Vector LLC currently distributes this code without intellectual property indemnification, warranty, claim of fitness of purpose, or any other guarantee under a GPL3 license.

#' @importFrom dplyr %>% ungroup summarize transmute summarise_each funs filter_
#' @importFrom stats sd setNames
#' @importFrom utils capture.output head
#' @importFrom lazyeval interp
NULL

localFrame <- function(d) {
  all(class(d) %in% c("tbl_df","tbl","data.frame"))
}

#' Compute usable summary of columns of tbl.
#'
#' @param x tbl or item that can be coerced into such.
#' @param countUnique logical, if true include unique non-NA counts.
#' @return summary of columns.
#'
#' @examples
#'
#' d <- data.frame(x=c(NA,2,3),y=factor(c(3,5,NA)),z=c('a',NA,'z'),
#'                 stringsAsFactors=FALSE)
#' replyr_summary(d)
#'
#' @export
replyr_summary <- function(x,countUnique=TRUE) {
  nrows <- replyr_nrow(x)
  cnames <- colnames(x)
  cmap <- seq_len(length(cnames))
  names(cmap) <- cnames
  numericCols <- cnames[replyr_testCols(x,is.numeric)]
  cclass <- replyr_colClasses(x)
  names(cclass) <- cnames
  # from http://stackoverflow.com/questions/34594641/dplyr-summary-table-for-multiple-variables
  # but the values as columns are not convenient.
  # see also http://stackoverflow.com/questions/26492280/non-standard-evaluation-nse-in-dplyrs-filter-pulling-data-from-mysql
  suppressWarnings({
   numSums <- lapply(numericCols,
                    function(ci) {
                      filter_criteria <- lazyeval::interp(~ !is.na(which_column), which_column = as.name(ci))
                      x %>% dplyr::select_(ci) %>%
                        filter_(filter_criteria) -> xsub
                      ngood <- replyr_nrow(xsub)
                      xsub %>% dplyr::summarise_each(dplyr::funs(min = min,
                                            # q25 = quantile(., 0.25),  # MySQL can't do this
                                            # median = median,          # MySQL can't do this
                                            # q75 = quantile(., 0.75),  # MySQL can't do this
                                            max = max,
                                            mean = mean,
                                            sd = sd)) %>%
                        dplyr::collect() %>% as.data.frame() -> si
                      nunique = NA
                      if(countUnique) {
                        xsub %>% replyr_uniqueValues(ci) %>% replyr_nrow() -> nunique
                      }
                      si <-  data.frame(column=ci,
                                        index=0,
                                        class='',
                                        nrows = nrows,
                                        nna = nrows - ngood,
                                        nunique = nunique,
                                        min = si$min,
                                        max = si$max,
                                        mean = si$mean,
                                        sd = si$sd,
                                        lexmin = NA_character_,
                                        lexmax = NA_character_,
                                        stringsAsFactors = FALSE)
                      si
                    })
   oSums <- lapply(setdiff(cnames,numericCols),
                    function(ci) {
                      filter_criteria <- lazyeval::interp(~ !is.na(which_column), which_column = as.name(ci))
                      x %>% dplyr::select_(ci) %>%
                        filter_(filter_criteria) -> xsub
                      ngood <- replyr_nrow(xsub)
                      # min/max don't work local data.frames for factors, but do for strings.
                      si <- data.frame(lexmin = NA_character_,
                                       lexmax = NA_character_,
                                       stringsAsFactors = FALSE)
                      good <- FALSE
                      tryCatch(
                        {
                        xsub %>% dplyr::summarise_each(dplyr::funs(lexmin = min,
                                                                   lexmax = max)) %>%
                            dplyr::collect() %>% as.data.frame() -> si;
                        si <- data.frame(lexmin = as.character(si$lexmin),
                                         lexmax = as.character(si$lexmax),
                                         stringsAsFactors = FALSE)
                        good <- TRUE
                        },
                        error = function(x) NULL
                      )
                      if((!good)&&(localFrame(xsub))) {
                        suppressWarnings(
                          xsub %>%
                            dplyr::collect() %>% as.data.frame() -> xsublocal
                        )
                        si <- data.frame(lexmin = min(as.character(xsublocal[[ci]])),
                                         lexmax = max(as.character(xsublocal[[ci]])),
                                         stringsAsFactors = FALSE)
                      }
                      nunique = NA
                      if(countUnique) {
                        xsub %>% replyr_uniqueValues(ci) %>% replyr_nrow() -> nunique
                      }
                      si <- data.frame(column=ci,
                                       index=0,
                                       class='',
                                       nrows = nrows,
                                       nna = nrows - ngood,
                                       nunique = nunique,
                                       min = NA_real_,
                                       max = NA_real_,
                                       mean = NA_real_,
                                       sd = NA_real_,
                                       lexmin = si$lexmin,
                                       lexmax = si$lexmax,
                                       stringsAsFactors = FALSE)
                      si
                    })
  })
  res <- dplyr::bind_rows(c(numSums,oSums))
  res$index <- cmap[res$column]
  classtr <- lapply(cclass,function(vi) {
    paste(vi,collapse=', ')
  })
  res$class <- classtr[res$column]
  res <- res[order(res$index),]
  res
}


