<!-- README.md is generated from README.Rmd. Please edit that file -->
This document describes `replyr`, an [R](https://cran.r-project.org) package available from [Github](https://github.com/WinVector/replyr) and [CRAN](https://CRAN.R-project.org/package=replyr).

To install from Github please try:

``` r
devtools::install_github("WinVector/replyr")
```

\[Note: the CRAN version of replyr currently has a bug in `replyr_summary` that is now fixed in the Github version. We will update the CRAN version after we get some more tests in place.\]

Introduction
------------

It comes as a bit of a shock for [R](https://cran.r-project.org) [`dplyr`](https://CRAN.R-project.org/package=dplyr) users when they switch from using a `tbl` implementation based on R in-memory `data.frame`s to one based on a remote database or service. A lot of the power and convenience of the `dplyr` notation is hard to maintain with these more restricted data service providers. Things that work locally can't always be used remotely at scale. It is emphatically not yet the case that one can practice with `dplyr` in one modality and hope to move to another back-end without significant debugging and work-arounds. The [`replyr`](https://github.com/WinVector/replyr) package attempts to provide practical data manipulation affordances.

<a href="https://www.flickr.com/photos/42988571@N08/18029435653" target="_blank"><img src="18029435653_4d64c656c8_z.jpg"> </a>

`replyr` supplies methods to get a grip on working with remote `tbl` sources (`SQL` databases, `Spark`) through `dplyr`. The idea is to add convenience functions to make such tasks more like working with an in-memory `data.frame`. Results still do depend on which `dplyr` service you use, but with `replyr` you have fairly uniform access to some useful functions.

`replyr` uniformly uses standard or paremtric interfaces (names of variables as strings) in favor of name capture so that you can easily program *over* `replyr`.

Primary `replyr` services include:

-   `replyr::let`
-   `replyr::gapply`
-   `replyr::replyr_*`

`replyr::let`
-------------

`replyr::let` allows execution of arbitrary code with substituted variable names (note this is subtly different than binding values for names as with `base::substitute`). This allows the user to write arbitrary `dplyr` code in the case of ["parametric variable names"](http://www.win-vector.com/blog/2016/12/parametric-variable-names-and-dplyr/) (that is when variable names are not known at coding time, but will become available later at run time as values in other variables) without directly using the `dplyr` "underbar forms" (and the direct use of `lazyeval::interp` and `.dots=stats::setNames` to use the `dplyr` "underbar forms").

Example:

``` r
library('dplyr')
```

``` r
# nice parametric function we write
ComputeRatioOfColumns <- function(d,NumeratorColumnName,DenominatorColumnName,ResultColumnName) {
  replyr::let(
    alias=list(NumeratorColumn=NumeratorColumnName,
               DenominatorColumn=DenominatorColumnName,
               ResultColumn=ResultColumnName),
    expr={
      # (pretend) large block of code written with concrete column names.
      # due to the let wrapper in this function it will behave as if it was
      # using the specified paremetric column names.
      d %>% mutate(ResultColumn=NumeratorColumn/DenominatorColumn)
    })()
}

# example data
d <- data.frame(a=1:5,b=3:7)

# example application
d %>% ComputeRatioOfColumns('a','b','c')
 #    a b         c
 #  1 1 3 0.3333333
 #  2 2 4 0.5000000
 #  3 3 5 0.6000000
 #  4 4 6 0.6666667
 #  5 5 7 0.7142857
```

`replyr::let` makes construction of abstract functions over `dplyr` controlled data much easier. It is designed for the case where the "`expr`" block is large sequence of statements and pipelines.

Note that `base::substitute` is not powerful enough to remap both names and values without some helper notation (see [here](http://stackoverflow.com/questions/22005419/dplyr-without-hard-coding-the-variable-names) for an using substitute. What we mean by this is show below:

``` r
library('dplyr')
```

Substitute with `quote` notation.

``` r
d <- data.frame(Sepal_Length=c(5.8,5.7),
                Sepal_Width=c(4.0,4.4),
                Species='setosa',
                rank=c(1,2))
eval(substitute(d %>% mutate(RankColumn=RankColumn-1),
                list(RankColumn=quote(rank))))
 #    Sepal_Length Sepal_Width Species rank RankColumn
 #  1          5.8         4.0  setosa    1          0
 #  2          5.7         4.4  setosa    2          1
```

Substitute with `as.name` notation.

``` r
eval(substitute(d %>% mutate(RankColumn=RankColumn-1),
                list(RankColumn=as.name('rank'))))
 #    Sepal_Length Sepal_Width Species rank RankColumn
 #  1          5.8         4.0  setosa    1          0
 #  2          5.7         4.4  setosa    2          1
```

Substitute without extra notation (errors-out).

``` r
eval(substitute(d %>% mutate(RankColumn=RankColumn-1),
                list(RankColumn='rank')))
 #  Error in mutate_impl(.data, dots): non-numeric argument to binary operator
```

Notice in both working cases the `dplyr::mutate` result landed in a column named `RankColumn` and not in the desired column `rank`. The `replyr::let` form is concise and works correctly.

Similarly `base::with` can not perform the needed name remapping, none of the following variations simulate a name to name substitution.

``` r
# rank <- NULL # hide binding of rank to function
env <- new.env()
assign('RankColumn',quote(rank),envir = env)
# assign('RankColumn',as.name('rank'),envir = env)
# assign('RankColumn',rank,envir = env)
# assign('RankColumn','rank',envir = env)
with(env,d %>% mutate(RankColumn=RankColumn-1))
```

Whereas `replyr::let` works and is succinct (though notice the required closing of the `replyr::let` block with an extra `()`).

``` r
replyr::let(
  alias=list(RankColumn='rank'),
  d %>% mutate(RankColumn=RankColumn-1)
)()
 #    Sepal_Length Sepal_Width Species rank
 #  1          5.8         4.0  setosa    0
 #  2          5.7         4.4  setosa    1
```

Note `replyr::let` only controls name bindings in the the scope of the `expr={}` block, and not inside functions called in the block. To be clear `replyr::let` is re-writing function arguments (which is how we use `dplyr::mutate` in the above example), but it is not re-writing data (which is why deeper in functions don't see re-namings). This means one can not parameterize a function from the outside. For example the following function can only be used parametrically if we re-map the data frame, or if `dplyr` itself (or a data adapter) implemented something like the view stack proposal found [here](http://www.win-vector.com/blog/2016/12/parametric-variable-names-and-dplyr/).

``` r
library('dplyr')
```

``` r
# example data
d <- data.frame(a=1:5,b=3:7)

# original function we do not have control of
ComputeRatioOfColumnsHardCoded <- function(d) {
  d %>% mutate(ResultColumn=NumeratorColumn/DenominatorColumn)
}

# wrapper to make function look parametric
ComputeRatioOfColumnsWrapped <- function(d,NumeratorColumnName,DenominatorColumnName,ResultColumnName) {
  d %>% replyr::replyr_mapRestrictCols(list(NumeratorColumn='a',
                                            DenominatorColumn='b')) %>%
    
    ComputeRatioOfColumnsHardCoded() %>%
    replyr::replyr_mapRestrictCols(list(a='NumeratorColumn',
                                        b='DenominatorColumn',
                                        c='ResultColumn'))
}

# example application
d %>% ComputeRatioOfColumnsWrapped('a','b','c')
 #    a b         c
 #  1 1 3 0.3333333
 #  2 2 4 0.5000000
 #  3 3 5 0.6000000
 #  4 4 6 0.6666667
 #  5 5 7 0.7142857
```

`replyr::let` is based on `gtools::strmacro` by Gregory R. Warnes, and the need for the final `()` to execute the returned function is left in because we have left `replyr::let` as a macro constructor as was the case with `gtools::strmacro`.

`replyr::gapply`
----------------

`replyr::gapply` is a "grouped ordered apply" data operation. Many calculations can be written in terms of this primitive, including per-group rank calculation (assuming your data services supports window functions), per-group summaries, and per-group selections. It is meant to be a specialization of ["The Split-Apply-Combine"](https://www.jstatsoft.org/article/view/v040i01) strategy with all three steps wrapped into a single operator.

Example:

``` r
library('dplyr')
```

``` r
d <- data.frame(group=c(1,1,2,2,2),
                order=c(.1,.2,.3,.4,.5))
rank_in_group <- . %>% mutate(constcol=1) %>%
          mutate(rank=cumsum(constcol)) %>% select(-constcol)
d %>% replyr::gapply('group',rank_in_group,ocolumn='order',decreasing=TRUE)
 #  # A tibble: 5 × 3
 #    group order  rank
 #    <dbl> <dbl> <dbl>
 #  1     2   0.5     1
 #  2     2   0.4     2
 #  3     2   0.3     3
 #  4     1   0.2     1
 #  5     1   0.1     2
```

The user supplies a function or pipeline that is meant to be applied per-group and the `replyr::gapply` wrapper orchestrates the calculation. In this example `rank_in_group` was assumed to know the column names in our data, so we directly used them instead of abstracting through `replyr::let`. `replyr::gapply` defaults to using `dplyr::group_by` as its splitting or partitioning control, but can also perform actual splits using 'split' ('base::split') or 'extract' (sequential extraction). Semantics are slightly different between cases given how `dplyr` treats grouping columns, the issue is illustrated in the difference between the definitions of `sumgroupS` and `sumgroupG` in [this example](https://github.com/WinVector/replyr/blob/master/checks/gapply.md)).

`replyr::replyr_*`
------------------

The `replyr::replyr_*` functions are all convenience functions supplying common functionality (such as `replyr::replyr_nrow`) that works across many data services providers. These are prefixed (instead of being `S3` or `S4` methods) so they do not interfere with common methods. Many of these functions can expensive (which is why `dplyr` does not provide them as a default), or are patching around corner cases (which is why these functions appear to duplicate `base::` and `dplyr::` capabilities). The issues `replyr::replyr_*` claim to patch around have all been filed as issues on the appropriate `R` packages and are documented [here](https://github.com/WinVector/replyr/tree/master/issues) (to confirm they are not phantoms).

Example: `replyr::replyr_summary` working on a database service (when `base::summary` does not).

``` r
d <- data.frame(x=c(1,2,2),y=c(3,5,NA),z=c(NA,'a','b'),
                stringsAsFactors = FALSE)
if (requireNamespace("RSQLite")) {
  my_db <- dplyr::src_sqlite(":memory:", create = TRUE)
  dRemote <- replyr::replyr_copy_to(my_db,d,'d')
} else {
  dRemote <- d # local stand in when we can't make remote
}
 #  Loading required namespace: RSQLite

summary(dRemote)
 #      Length Class          Mode
 #  src 2      src_sqlite     list
 #  ops 3      op_base_remote list

replyr::replyr_summary(dRemote)
 #    column index     class nrows nna nunique min max     mean        sd lexmin lexmax
 #  1      x     1   numeric     3   0       2   1   2 1.666667 0.5773503   <NA>   <NA>
 #  2      y     2   numeric     3   1       2   3   5 4.000000 1.4142136   <NA>   <NA>
 #  3      z     3 character     3   1       2  NA  NA       NA        NA      a      b
```

Data types, capabilities, and row-orders all vary a lot as we switch remote data services. But the point of `replyr` is to provide at least some convenient version of typical functions such as: `summary`, `nrow`, unique values, and filter rows by values in a set.

`replyr` Data services
----------------------

This is a *very* new package with no guarantees or claims of fitness for purpose. Some implemented operations are going to be slow and expensive (part of why they are not exposed in `dplyr` itself).

We will probably only ever cover:

-   Native `data.frame`s (and `tbl`/`tibble`)
-   `RMySQL`
-   `RPostgreSQL`
-   `SQLite`
-   `sparklyr` (`Spark` 2 preferred)

Additional functions
--------------------

Additional `replyr` functions include: `replyr::replyr_filter` and `replyr::replyr_inTest`. These are designed to subset data based on a columns values being in a given set. These allow selection of rows by testing membership in a set (very useful for partitioning data). Example below:

``` r
library('dplyr')
```

``` r
values <- c(2)
dRemote %>% replyr::replyr_filter('x',values)
 #  Source:   query [?? x 3]
 #  Database: sqlite 3.11.1 [:memory:]
 #  
 #        x     y     z
 #    <dbl> <dbl> <chr>
 #  1     2     5     a
 #  2     2    NA     b
```

Commentary
----------

I would like this to become a bit of a ["stone soup"](https://en.wikipedia.org/wiki/Stone_Soup) project. If you have a neat function you want to add please contribute a pull request with your attribution and assignment of ownership to [Win-Vector LLC](http://www.win-vector.com/) (so Win-Vector LLC can control the code, which we are currently distributing under a GPL3 license) in the code comments.

There are a few (somewhat incompatible) goals for `replyr`:

-   Providing missing convenience functions that work well over all common `dplyr` service providers. Examples include `replyr_summary`, `replyr_filter`, and `replyr_nrow`.
-   Providing a basis for "row number free" data analysis. SQL back-ends don't commonly supply row number indexing (or even deterministic order of rows), so a lot of tasks you could do in memory by adjoining columns have to be done through formal key-based joins.
-   Providing emulations of functionality missing from non-favored service providers (such as windowing functions, `quantile`, `sample_n`, `cumsum`; missing from `SQLite` and `RMySQL`).
-   Working around corner case issues, and some variations in semantics.
-   Sheer bull-headedness in emulating operations that don't quite fit into the pure `dplyr` formulation.

Good code should fill one important gap and work on a variety of `dplyr` back ends (you can test `RMySQL`, and `RPostgreSQL` using docker as mentioned [here](http://www.win-vector.com/blog/2016/11/mysql-in-a-container/) and [here](http://www.win-vector.com/blog/2016/02/databases-in-containers/); `sparklyr` can be tried in local mode as described [here](http://spark.rstudio.com)). I am especially interested in clever "you wouldn't thing this was efficiently possible, but" solutions (which give us an expanded grammar of useful operators), and replacing current hacks with more efficient general solutions. Targets of interest include `sample_n` (which isn't currently implemented for `tbl_sqlite`), `cumsum`, and `quantile` (currently we have an expensive implementation of `quantile` based on binary search: `replyr::replyr_quantile`).

`replyr` services include:

-   Moving data into or out of the remote data store (including adding optional row numbers), `replyr_copy_to` and `replyr_copy_from`.
-   Basic summary info: `replyr_nrow`, `replyr_dim`, and `replyr_summary`.
-   Random row sampling (like `dplyr::sample_n`, but working with more service providers). Some of this functionality is provided by `replyr_filter` and `replyr_inTest`.
-   Emulating [The Split-Apply-Combine Strategy](https://www.jstatsoft.org/article/view/v040i01), which is the purpose `gapply`, `replyr_split`, and `replyr_bind_rows`.
-   Emulating `tidyr` gather/spread (or pivoting and anti-pivoting), which is the purpose of `replyr_gather` and `replyr_spread` (still under development).
-   Patching around differences in `dplyr` services providers (and documenting the reasons for the patches).
-   Making use of "parameterized names" much easier (that is: writing code does not know the name of the column it is expected to work over, but instead takes the column name from a user supplied variable).

Additional desired capabilities of interest include:

-   `cumsum` or row numbering (interestingly enough if you have row numbering you can implement cumulative sum in log-n rounds using joins to implement pointer chasing/jumping ideas, but that is unlikely to be practical, `lag` is enough to generate next pointers, which can be boosted to row-numberings).
-   Inserting random values (or even better random unique values) in a remote column. Most service providers have a pseudo-random source you can use.

Conclusion
----------

`replyr` is package for speeding up reliable data manipulation using `dplyr` (especially on databases and `Spark`). It is also a good central place to collect patches and fixes needed to work around corner cases and semantic variations between versions of data sources (such as `Spark 1.6.2` versions `Spark 2.0.0`).

Clean up
--------

``` r
rm(list=ls())
gc()
 #            used (Mb) gc trigger (Mb) max used (Mb)
 #  Ncells  503669 26.9     940480 50.3   940480 50.3
 #  Vcells 1186724  9.1    2100726 16.1  2085455 16.0
```
