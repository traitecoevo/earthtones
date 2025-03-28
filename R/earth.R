
##' Earthtones downloads a satellite image from google earth, translates the image into a perceptually uniform color space, runs one of a few different clustering algorithms on the colors in the image searching for a user supplied number of colors, and returns the resulting color palette.  
##'
##'
##' @title Find the color palette of a particular place on earth
##'
##' @param latitude center of the returned satellite image
##'
##' @param longitude center of the returned satellite image
##'
##' @param zoom generally this should be between 2 and 20; higher values zoom in closer to the target lat/long; for details see \code{\link[ggmap]{get_map}}
##'
##' @param number_of_colors how many colors do you want?
##' 
##' @param method specifies clustering method. Options are \code{\link[stats]{kmeans}} or \code{\link[cluster]{pam}} (partitioning around medoids)
##' 
##' @param sampleRate subsampling factor - bigger number = more subsampling and less computation
##' 
##' @param include.map logical flag that determines whether to return the satellite image with the data object; for exploring the world leave this as TRUE; if/when you settle on a color scheme and are using this within a visualization, change to FALSE and the function will return a normal R-style color palette.  
##' 
##' @param ... additional arguments passed to \code{\link[ggmap]{get_map}}
##'
##' @details Different parts of the world have different color diversity.  Zoom is also especially important.  To visualize the results, simply print the resulting object.  
##' 
##' @seealso \code{\link[ggmap]{get_map}}, \code{\link[stats]{kmeans}} 
##' @import grDevices stats graphics
##' @export
##' @examples
##' 
##' \dontrun{
##' 
##' get_earthtones(latitude = 24.2, longitude = -77.88, zoom = 11, number_of_colors = 5)
##' }
##' 

get_earthtones <- function(latitude = 50.759, longitude = -125.673,
                           zoom = 11, number_of_colors = 3, method = "pam",
                           sampleRate = 500, include.map = TRUE,
                           provider = "Esri.WorldImagery", ...) {
  
  # enforce practical zoom limits
  min_zoom <- 0
  max_zoom <- 13
  
  if (!is.numeric(zoom) || length(zoom) != 1 || zoom < min_zoom || zoom > max_zoom) {
    stop(sprintf("Zoom level must be a single numeric value between %d (world view) and %d (maximum detail). Provided: %s",
                 min_zoom, max_zoom, zoom))
  }
  
  supported_methods <- c("kmeans", "pam")
  if (!method %in% supported_methods) {
    stop(paste0("Method specified is invalid or unsupported. Choose from: ",
                paste(supported_methods, collapse = ", ")))
  }
  
  # Create an sf point geometry and transform to Web Mercator for bbox
  point_sf <- sf::st_sfc(sf::st_point(c(longitude, latitude)), crs = 4326)
  point_3857 <- sf::st_transform(point_sf, 3857)
  
  # Define bbox around the point in meters, scaled roughly by zoom
  bbox_size <- 5000 * (15 - zoom)  
  bbox <- sf::st_bbox(sf::st_buffer(point_3857, dist = bbox_size))
  
  # Get raster tiles from maptiles (static raster image)
  map_raster <- maptiles::get_tiles(x = bbox, provider = provider, crop = TRUE, zoom = zoom)
  
  # Extract colors from the raster image
  col.out <- get_colors_from_raster(map_raster, number_of_colors, method, sampleRate)
  
  if (include.map) {
    out.col <- list(pal = col.out, map = map_raster)
    return(structure(out.col, class = "palette"))
  } else {
    return(col.out)
  }
}

# Function to extract colors from raster using clustering
get_colors_from_raster <- function(raster_img, number_of_colors, clust.method, subsampleRate) {
  if (subsampleRate < 300 && clust.method == "pam") {
    message("Pam can be slow; consider a larger sampleRate.")
  }
  
  # Extract raster values explicitly as a matrix
  raster_values <- terra::values(raster_img, mat = TRUE)
  raster_values <- na.omit(raster_values)
  
  # Ensure raster_values is a matrix with 3 columns (RGB)
  if (!is.matrix(raster_values) || ncol(raster_values) < 3) {
    stop("Raster values extraction failed or raster does not have RGB bands.")
  }
  
  # Subsample for speed
  if (subsampleRate > 1) {
    raster_values <- raster_values[seq(1, nrow(raster_values), by = subsampleRate), ]
  }
  
  # RGB to LAB conversion
  col.vec.lab <- convertColor(raster_values / 255, from = "sRGB", to = "Lab")
  lab.restructure <- data.frame(L = col.vec.lab[, 1], a = col.vec.lab[, 2], b = col.vec.lab[, 3])
  
  if (clust.method == "kmeans") {
    out <- kmeans(lab.restructure, number_of_colors)
    out.rgb <- convertColor(out$centers, from = "Lab", to = "sRGB")
  } else if (clust.method == "pam") {
    if (!requireNamespace("cluster", quietly = TRUE)) {
      stop("The 'cluster' package is required for method='pam'. Please install it.")
    }
    out <- cluster::pam(lab.restructure, k = number_of_colors)
    out.rgb <- convertColor(out$medoids, from = "Lab", to = "sRGB")
  }
  
  # Clamp RGB values to valid range [0,1]
  out.rgb[out.rgb < 0] <- 0
  out.rgb[out.rgb > 1] <- 1
  
  return(rgb(out.rgb))
}


# Print method for palette
print.palette <- function(x, ...) {
  number_of_colors <- length(x$pal)
  par(mfrow = c(2, 1), mar = c(0.5, 0.5, 0.5, 0.5))
  terra::plotRGB(x$map)
  image(1:number_of_colors, 1, as.matrix(1:number_of_colors), col = x$pal,
        ylab = "", xlab = "", xaxt = "n", yaxt = "n", bty = "n")
}