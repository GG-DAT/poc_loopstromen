poi <- "attractiepark"
output_dir <- file.path(getwd(), "Output", poi)

csv_data_voorna <- read.csv(file.path(getwd(), paste0(poi, "_data_Voorna.csv")), 
                     colClasses = "character", header = TRUE, fileEncoding = "latin1")

if (poi == "cultuur") {
  csv_data_extra <- read.csv(
    file.path(getwd(), "bioscoop_data_voorna.csv"), 
    colClasses = "character", 
    header = TRUE, 
    fileEncoding = "latin1"
  )
  
  csv_data <- rbind(csv_data_voorna, csv_data_extra)
}

if (poi == "sport") {
  csv_data_extra <- read.csv(
    file.path(getwd(), "ijsbaan_data_voorna.csv"), 
    colClasses = "character", 
    header = TRUE, 
    fileEncoding = "latin1"
  )
  
  csv_data <- rbind(csv_data_voorna, csv_data_extra)
}

csv_data_voorna <- csv_data_voorna %>%
  mutate(
    tracker_id = round(as.numeric(as.character(tracker_id)), 0),
    journey_distance = round(as.numeric(as.character(journey_distance)), 0)
  ) %>%
  group_by(poi_id) %>%
  mutate(
    aantal_unieke_trackers = n_distinct(tracker_id),
    gemiddelde_journey_distance = sum(journey_distance) / n()
  ) %>%
  ungroup()

#csv_data_voorna = subset(csv_data_voorna, gemiddelde_journey_distance > journey_distance_filter & aantal_unieke_trackers > tracker_filter) # Filteren data

# -------- GRAFIEK 5: Modal split per afstandsklasse (niet per poi, alles samen) --------

#csv_data_voorna$infra_distance = ifelse(csv_data_voorna$trip_mode == "TRAIN", 100, csv_data_voorna$infra_distance)
#csv_data_voorna$observed_distance = ifelse(csv_data_voorna$trip_mode == "TRAIN", 100, csv_data_voorna$observed_distance)

modal_split_voorna_afstandsklassen <- csv_data_voorna %>%
  mutate(weight = round(as.numeric(as.character(weight)), 5)) %>%
  filter(trip_mode != 'TRAIN') %>% #van trein klopt de afstand niet
  filter(trip_mode != 'UNKNOWN') %>% #van trein klopt de afstand niet
  mutate(
    infra_distance = as.numeric(as.character(infra_distance)),
    afstand_bin = cut(infra_distance, breaks = c(0, 500, 1000, 1500, 2000, 2500, 3000, 5000, 40000),
                      include.lowest = TRUE, right = FALSE,
                      labels = c("0–500", "500–1000", "1000–1500", "1500–2000", "2000–2500",
                                 "2500–3000", "3000–5000", "5000–40000"))
  )

modal_split_voorna_afstandsklassen <- csv_data_voorna %>%
  mutate(weight = round(as.numeric(as.character(weight)), 5)) %>%
  filter(trip_mode != 'TRAIN') %>% #van trein klopt de afstand niet
  filter(trip_mode != 'UNKNOWN') %>% #van trein klopt de afstand niet
  mutate(
    infra_distance = as.numeric(as.character(infra_distance)),
    afstand_bin = cut(infra_distance, breaks = c(0, 200, 400, 600, 800, 1000, 1200, 1400, 1600, 2400, 3200, 5000, 7000, 40000),
                      include.lowest = TRUE, right = FALSE,
                      labels = c("0–200", "200–400", "400–600", "600–800", "800–1000",
                                 "1000–1200", "1200–1400", "1400-1600","1600-2400","2400-3200","3200-5000","5000-7000", "7000–40000"))
  )

modal_bins_voorna_summary <- modal_split_voorna_afstandsklassen %>%
  group_by(afstand_bin) %>%
  summarise(
    frequentie = n(),
    totaal = sum(weight),
    aantal_pois = n_distinct(poi_id),
    voet = sum(weight[trip_mode == "FOOT"]),
    fiets = sum(weight[trip_mode == "BIKE"]),
    btm = sum(weight[trip_mode %in% c("TRAM", "BUS", "METRO", "LIGHTRAIL","FERRY")]),
    auto = sum(weight[trip_mode == "CAR"]),
    aandeel_voet = voet / totaal,
    aandeel_fiets = fiets / totaal,
    aandeel_btm = btm / totaal,
    aandeel_auto = auto / totaal,
    .groups = "drop"
  )

modal_bins_voorna_long <- modal_bins_voorna_summary %>%
  select(afstand_bin, totaal, starts_with("aandeel_")) %>%
  pivot_longer(cols = starts_with("aandeel_"), names_to = "vervoermiddel", values_to = "aandeel") %>%
  mutate(
    vervoermiddel = str_replace(vervoermiddel, "aandeel_", "")
  )

modal_bins_voorna_long <- left_join(modal_bins_voorna_long, modal_bins_voorna_summary %>% select(afstand_bin, frequentie), by = "afstand_bin")
modal_bins_voorna_long <- left_join(modal_bins_voorna_long, modal_bins_voorna_summary %>% select(afstand_bin, aantal_pois), by = "afstand_bin")

modal_bins_voorna_long <- modal_bins_voorna_long %>%
  mutate(frequentie_totaal_label = paste0("pois=", aantal_pois, "\n n=", frequentie))

# Plot p5
p5 <- ggplot(modal_bins_voorna_long, aes(x = factor(afstand_bin), y = aandeel, fill = vervoermiddel)) +
  geom_bar(stat = "identity")  +
  geom_text(aes(label = frequentie_totaal_label, y = 0.97), vjust = 0, hjust = 0.5, size = 3, angle = 0) +
  labs(
    title = paste("Modal split voor/natransport per afstandsklasse -", poi),
    x = "Afstandsklassen (meters)", y = "Aandeel", fill = "Vervoermiddel"
  ) +
  scale_fill_manual(values = c(
    "voet" = "#A58AFF",
    "fiets" = "#C49A00",
    "btm" = "#F8766D",
    "auto" = "#00C094"
  )) +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.25)) +
  geom_text(
    data = subset(modal_bins_voorna_long, vervoermiddel == "voet"),
    aes(label = scales::percent(aandeel, accuracy = 1)),
    position = position_stack(vjust = 0.01),
    color = "black", size = 3)

p5

# Opslaan
ggsave(filename = file.path(output_dir, "5_modal_split_voorna_per_afstandsklasse.jpg"), plot = p5, width = 8, height = 6, dpi = 300)


# -------- GRAFIEK 6: Functie schatten --------

fractie_lopen_per_afstandsklasse <- subset(modal_bins_voorna_long, vervoermiddel == "voet")
fractie_lopen_per_afstandsklasse <- fractie_lopen_per_afstandsklasse %>%
  group_by(afstand_bin) %>%
  mutate(
    afstand_bin = str_replace_all(afstand_bin, "–", "-")  # Vervang en-dash door gewoon koppelteken
  ) %>%
  separate(afstand_bin, into = c("min_afstand", "max_afstand"), sep = "-") %>%
  mutate(
    min_afstand = as.numeric(min_afstand),
    max_afstand = as.numeric(max_afstand),
    x = (min_afstand + max_afstand) / 2000
  ) %>%
  ungroup()

x <- fractie_lopen_per_afstandsklasse$x 
y_voet <- fractie_lopen_per_afstandsklasse$aandeel
gewichten <- fractie_lopen_per_afstandsklasse$totaal
  
model_gaussian_bins <- nlsLM(
  y_voet ~ gaussian(x, 1, c),
  start = list( c = 2)#,#,
  #weights = gewichten 
)
summary_model_gaussian_bins <- capture.output(summary(model_gaussian_bins))
writeLines(summary_model_gaussian_bins, paste0(output_dir, "/functie_fractie_voorna_lopen_bins_", poi, ".txt") )

x_fit <- seq(min(x), max(x), length.out = 200)
y_fit <- predict(model_gaussian_bins, list(x = x_fit))
fit_bins <- data.frame(x = x_fit, y = y_fit)
coefs_bins <- coef(model_gaussian_bins)
a_bins <- round(as.numeric(coefs_bins["a"]),3)
c_bins <- round(as.numeric(coefs_bins["c"]),2)
formule_fit_bins <- paste0("y == ", a_bins, " * exp(-x^2 / (2 * (", c_bins, ")^2))")
formule_fit_bins <- parse(text = formule_fit_bins)


p6 <- ggplot(fractie_lopen_per_afstandsklasse, aes(x = x, y = aandeel)) +
  geom_point(color = "#FB61D7", size = 3, shape = 18) + 
  labs(
    title = paste0("Fractie lopen (als voor/natransport trein) per afstandsklasse - ", poi),
    x = "midden van afstandsklasse (km)", y = "Fractie lopen"
  ) +
  geom_line(data = fit_bins, aes(x = x, y = y), color = "#FB61D7", size = 1) +
  annotate("text", x = 2, y = 1, label = formule_fit_bins, parse = TRUE, color = "#FB61D7", hjust = 0)+
  scale_x_continuous(limits = c(0, 5)) +
  coord_cartesian(ylim = c(0, 1)) +
  theme_minimal()

p6


ggsave(filename = file.path(output_dir, paste0("6_functie_fitting_aandeel_lopen_geen_weging.jpg")), plot = p6, width = 8, height = 6, dpi = 300)


# modal_split_voorna_per_poi <- csv_data_voorna %>%
#   mutate(weight = round(as.numeric(as.character(weight)), 5)) %>%
#   mutate(infra_distance = round(as.numeric(as.character(infra_distance)), 5)) %>%
#   filter(trip_mode != 'TRAIN') %>% #van trein klopt de afstand niet
#   filter(trip_mode != 'UNKNOWN') %>% #van trein klopt de afstand niet
#   group_by(poi_id) %>%
#   summarise(
#     frequentie = n(),
#     totaal = sum(weight),
#     aantal_pois = n_distinct(poi_id),
#     voet = sum(weight[trip_mode == "FOOT"]),
#     fiets = sum(weight[trip_mode == "BIKE"]),
#     btm = sum(weight[trip_mode %in% c("TRAM", "BUS", "METRO", "LIGHTRAIL")]),
#     auto = sum(weight[trip_mode == "CAR"]),
#     aandeel_voet = voet / totaal,
#     aandeel_fiets = fiets / totaal,
#     aandeel_btm = btm / totaal,
#     aandeel_auto = auto / totaal,
#     gemiddelde_ritlengte = sum(infra_distance) / n(),
#     .groups = "drop"
#   )


# # -------- LONG DF 3: FRACTIES VOOR/NA --------
# modal_split_voor_na = subset(modal_split, aantal_trips_trein > 0)
# 
# modal_split_long_frac_voor_na <- modal_split_voor_na %>%
#   select(naam, poi_id, station_naam, afstand_poi_station, type_station, aantal_trips_trein,
#          matches("^fractie_station_(lopen|lopen_en_trein)_gewogen$")) %>%
#   pivot_longer(
#     cols = starts_with("fractie_"),
#     names_to = "vervoermiddel",
#     values_to = "fractie"
#   ) %>%
#   mutate(
#     vervoermiddel = str_replace(vervoermiddel, "fractie_", ""),
#     vervoermiddel = str_replace(vervoermiddel, "_gewogen", ""),
#     naam_afstand = paste0(naam, ", ", afstand_poi_station)
#   )
# # -------- GRAFIEK 5: Scatter afstand vs voet voor/na trein (per poi) --------
# 
# p5 <- ggplot(filter(modal_split_long_frac_voor_na, vervoermiddel == "station_lopen_en_trein"),
#              aes(x = afstand_poi_station, y = fractie, color = type_station)) +
#   geom_point() +
#   geom_text(aes(label = aantal_trips_trein), vjust = -0.5, size = 3) +  # Labels toevoegen
#   scale_color_brewer(palette = "Set1") +
#   labs(
#     title = paste("Afstand tot station vs aandeel trein -", poi),
#     x = "Afstand tot station (meter)", y = "Aandeel lopen", color = "Type station"
#   ) +
#   scale_x_continuous(labels = label_comma()) +
#   theme_minimal()
# 
# p5
# 
# ggsave(filename = file.path(output_dir, "5_scatter_aandeel_voor_na_lopen.jpg"), plot = p5, width = 8, height = 6, dpi = 300)
# 

# -------- GRAFIEK 7: Functie schatten --------
# functie schatten door mid afstandsklasse trein fractie
# afstand_labels <- levels(modal_split_voorna_afstandsklassen$afstand_bin)
# afstand_middens <- sapply(strsplit(afstand_labels, "–|–|-"), function(x) {
#   bounds <- as.numeric(x)
#   mean(bounds)
# })
# fractie_voor_na_voet_per_afstandsklasse <- subset(modal_bins_voorna_long, vervoermiddel == "voet")
# fractie_voor_na_voet_per_afstandsklasse$x <- afstand_middens

# Curve fitting


