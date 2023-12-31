# Load required libraries
library(knitr) # for dynamic report generation (documentation)
library(data.table) # for data manipulation
library(ggplot2) # for visualization
library(ompr) # for modelling
library(sf) # for spatial vector data
library(tmap) # for thematic mapping
library(geosphere) # for handling long & lat computations
library(leaflet) # for javascript interactive maps
library(ompr.roi) # for optimization
library(ROI.plugin.glpk) # for mixed integers optimization
library(dplyr)
# Loading Nigeria Towns
Towns <- read.csv("D:/Project Analytics/R projects/DATA/NigeriaTowns.csv")
show(Towns)

# Displaying the Towns on leaflet
leaflet(data = Towns) %>% addTiles() %>%
  addMarkers(~Longitude, ~Latitude, popup = ~Town, label = ~Town)

# Convert the data frame to an sf object
Towns_sf <- st_as_sf(Towns, coords = c("Longitude", "Latitude"))

# Create a simple tmap object
map <- tm_shape(Towns_sf) +
  tm_tiles() +
  tm_markers(popup.vars = "Town", label = "Town")

# Display the map
map

# Data Preparation
town_geo <- Towns[, c("Longitude", "Latitude")]

# Modelling: use the "ompr" package

# Specify the dimensions of the distance matrix
n <- nrow(Towns)

# Create a distance extraction function
dist_fun <- function(i, j) {
  vapply(seq_along(i), function(k) {
    distHaversine(
      town_geo[i[k], ],
      town_geo[j[k], ]
    ) / 1000  # Convert meters to kilometers
  }, numeric(1L))
}

# First model
model <- MILPModel() %>%
  # Create a variable that is 1 iff we travel from city i to j
  add_variable(x[i, j], i = 1:n, j = 1:n, 
               type = "integer", lb = 0, ub = 1) %>%
  
  # A helper variable for the MTZ formulation of the tsp
  add_variable(u[i], i = 1:n, lb = 1, ub = n) %>% 
  
  # Minimize travel distance
  set_objective(
    sum_expr(colwise(dist_fun(i, j)) * x[i, j], i = 1:n, j = 1:n),
    "min"
  ) %>%
  
  # You cannot go to the same city
  set_bounds(x[i, i], ub = 0, i = 1:n) %>%
  
  # Leave each city
  add_constraint(sum_expr(x[i, j], j = 1:n) == 1, i = 1:n) %>%
  
  # Visit each city
  add_constraint(sum_expr(x[i, j], i = 1:n) == 1, j = 1:n) %>%
  
  # Ensure no subtours (arc constraints)
  add_constraint(u[i] >= 2, i = 2:n) %>% 
  add_constraint(u[i] - u[j] + 1 <= (n - 1) * (1 - x[i, j]), i = 2:n, j = 2:n)

# To solve the model
result <- solve_model(model, with_ROI(solver = "glpk", verbose = TRUE))

# Get the route distance
result_val <- round(objective_value(result), 2)

paste0('Total distance: ',result_val,'km')


# How does this route look on a map?
solution <- get_solution(result, x[i, j]) %>% 
  filter(value > 0)

paths <- select(solution, i, j) %>% 
  rename(from = i, to = j) %>% 
  mutate(trip_id = row_number()) %>% 
  inner_join(Towns, by = c("from" = "id"))

paths_leaflet <- paths[1,]
paths_row <- paths[1,]

for (i in 1:n) {
  paths_row <- paths %>% filter(from == paths_row$to[1])
  
  paths_leaflet <- rbind(paths_leaflet, paths_row)
}

leaflet() %>% 
  addTiles() %>%
  addMarkers(data = Towns, ~Longitude, ~Latitude, popup = ~Town, label = ~Town) %>% 
  addPolylines(data = paths_leaflet, ~Longitude, ~Latitude, weight = 2)


