context("earthtones")

test_that("returns normal", {
  expect_is(get_earthtones(), "palette")
  expect_is(get_earthtones(method = "kmeans"), "palette")
  expect_null(print(get_earthtones()))
  expect_is(get_earthtones(include_map = FALSE), "character")
  expect_message(get_earthtones(sample_rate = 250))
})

test_that("test stop() errors", {
  expect_error(earthtones::get_earthtones(method = "42"), message = "hello method.*")
  expect_error(
    if (!requireNamespace("cluster", quietly = TRUE)) {
      earthtones::get_earthtones(method = "pam")
    } else {
      stop("method")
    },
    message = "method.*"
  )
})
