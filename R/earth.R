##' Download a satellite image from a selected provider, extract dominant
##' colors, and generate an earth-tone palette.
##'
##' @title Extract Color Palettes from Satellite Imagery
##'
##' @param latitude Numeric. Latitude coordinate for the center of the satellite
##'     image.
##'
##' @param longitude Numeric. Longitude coordinate for the center of the
##'     satellite image.
##'
##' @param zoom Numeric. Zoom level between 0 (whole world) and 13
##'     (high detail). Higher values zoom in closer.
##'
##' @param number_of_colors Numeric. Number of dominant colors to extract.
##'
##' @param method Character. Clustering method to identify dominant colors.
##'     Options are \code{"kmeans"} (\code{\link[stats]{kmeans}}) or
##'     \code{"pam"} (\code{\link[cluster]{pam}} - partitioning around medoids).
##'
##' @param sample_rate Numeric. Subsampling factor; higher values reduce
##'     computation by sampling fewer pixels.
##'
##' @param include_map Logical. If \code{TRUE}, returns both the color palette
##'     and the satellite image raster. If \code{FALSE}, returns only the color
##'     palette.
##'
##' @param provider Character. Tile provider for satellite imagery. Currently
##'     supports \code{"Esri.WorldImagery"}.
##'
##' @param ... Additional arguments passed to internal functions (currently
##'     unused).
##'
##' @details
##' The function retrieves satellite imagery from the specified provider,
##' extracts colors by converting the imagery into a perceptually uniform color
##' space, and applies a clustering algorithm to determine dominant colors. Zoom
##' level and location significantly influence the palette generated.
##'
##' @return An object of class \code{"palette"} if \code{include_map = TRUE},
##'     containing:
##' \itemize{
##'   \item \code{pal}: A vector of hexadecimal color codes representing the
##'       dominant colors.
##'   \item \code{map}: A raster image object of the satellite imagery.
##' }
##' If \code{include_map = FALSE}, returns a vector of hexadecimal color codes.
##'
##' @seealso \code{\link[maptiles]{get_tiles}}, \code{\link[stats]{kmeans}},
##'     \code{\link[cluster]{pam}}
##' @import grDevices stats graphics sf maptiles
##' @export
##' @examples
##' \dontrun{
##' # Get a palette for a location in the Bahamas
##' get_earthtones(latitude = 24.2, longitude = -77.88, zoom = 11,
##'                number_of_colors = 5)
##'
##' # Return palette only, without map
##' get_earthtones(latitude = 24.2, longitude = -77.88,
##'                zoom = 11, number_of_colors = 5, include_map = FALSE)
##' }
##'
get_earthtones <- function(latitude = 50.759, longitude = -125.673,
                           zoom = 11, number_of_colors = 3, method = "pam",
                           sample_rate = 500, include_map = TRUE,
                           provider = "Esri.WorldImagery", ...) {
  # enforce practical zoom limits
  min_zoom <- 0
  max_zoom <- 13

  if (!is.numeric(zoom) || length(zoom) != 1 || zoom < min_zoom ||
    zoom > max_zoom) {
    stop(sprintf(
      paste0(
        "Zoom level must be a single numeric value between %d",
        " (world view) and %d (maximum detail). Provided: %s"
      ),
      min_zoom, max_zoom, zoom
    ))
  }

  supported_methods <- c("kmeans", "pam")
  if (!method %in% supported_methods) {
    stop(paste0(
      "Method specified is invalid or unsupported. Choose from: ",
      paste(supported_methods, collapse = ", ")
    ))
  }

  # right now just esri
  supported_providers <- c("Esri.WorldImagery")

  if (!(provider %in% supported_providers)) {
    stop(sprintf(
      "Provider '%s' is not supported. Choose from: %s",
      provider, paste(supported_providers, collapse = ", ")
    ))
  }

  # Create an sf point geometry and transform to Web Mercator for bbox
  point_sf <- sf::st_sfc(sf::st_point(c(longitude, latitude)), crs = 4326)
  point_3857 <- sf::st_transform(point_sf, 3857)

  # Define bbox around the point in meters, scaled roughly by zoom
  bbox_size <- 5000 * (15 - zoom)
  bbox <- sf::st_bbox(sf::st_buffer(point_3857, dist = bbox_size))

  # Get raster tiles from maptiles (static raster image)
  map_raster <- maptiles::get_tiles(
    x = bbox, provider = provider, crop = TRUE,
    zoom = zoom
  )

  # Extract colors from the raster image
  col_out <- get_colors_from_raster(
    map_raster, number_of_colors, method,
    sample_rate
  )

  if (include_map) {
    out_col <- list(pal = col_out, map = map_raster)
    structure(out_col, class = "palette")
  } else {
    col_out
  }
}

##' Extract Dominant Colors from Raster Image Using Clustering
##'
##' @param raster_img Raster object containing satellite imagery data.
##' @param number_of_colors Numeric. Number of dominant colors to extract.
##' @param clust_method Character. Clustering method; options are
##'     \code{"kmeans"} or \code{"pam"}.
##' @param subsample_rate Numeric. Subsampling factor to improve performance;
##'     higher values reduce computation.
##'
##' @return Vector of hexadecimal color codes representing dominant colors.
##' @noRd
get_colors_from_raster <- function(raster_img, number_of_colors, clust_method,
                                   subsample_rate) {
  if (subsample_rate < 300 && clust_method == "pam") {
    message("Pam can be slow; consider a larger sample_rate.")
  }

  # Extract raster values explicitly as a matrix
  raster_values <- terra::values(raster_img, mat = TRUE)
  raster_values <- na.omit(raster_values)

  # Ensure raster_values is a matrix with 3 columns (RGB)
  if (!is.matrix(raster_values) || ncol(raster_values) < 3) {
    stop("Raster values extraction failed or raster does not have RGB bands.")
  }

  # Subsample for speed
  if (subsample_rate > 1) {
    raster_values <- raster_values[seq(1, nrow(raster_values),
      by = subsample_rate
    ), ]
  }

  # RGB to LAB conversion
  col_vec_lab <- convertColor(raster_values / 255, from = "sRGB", to = "Lab")
  lab_restructure <- data.frame(
    L = col_vec_lab[, 1], a = col_vec_lab[, 2],
    b = col_vec_lab[, 3]
  )

  if (clust_method == "kmeans") {
    out <- kmeans(lab_restructure, number_of_colors)
    out_rgb <- convertColor(out$centers, from = "Lab", to = "sRGB")
  } else if (clust_method == "pam") {
    if (!requireNamespace("cluster", quietly = TRUE)) {
      stop(paste0(
        "The 'cluster' package is required for method='pam'.",
        " Please install it."
      ))
    }
    out <- cluster::pam(lab_restructure, k = number_of_colors)
    out_rgb <- convertColor(out$medoids, from = "Lab", to = "sRGB")
  }

  # Clamp RGB values to valid range [0,1]
  out_rgb[out_rgb < 0] <- 0
  out_rgb[out_rgb > 1] <- 1

  rgb(out_rgb)
}

##' Print Method for Palette Objects
##'
##' Visualizes the palette and associated satellite image.
##'
##' @param x An object of class \code{"palette"}.
##' @param ... Additional arguments passed to plotting methods.
##'
##' @return No return value; called for its side effect of plotting.
##' @exportS3Method print palette
print.palette <- function(x, ...) {
  number_of_colors <- length(x$pal)
  par(mfrow = c(2, 1), mar = c(0.5, 0.5, 0.5, 0.5))
  terra::plotRGB(x$map)
  image(1:number_of_colors, 1, as.matrix(1:number_of_colors),
    col = x$pal,
    ylab = "", xlab = "", xaxt = "n", yaxt = "n", bty = "n"
  )
}
