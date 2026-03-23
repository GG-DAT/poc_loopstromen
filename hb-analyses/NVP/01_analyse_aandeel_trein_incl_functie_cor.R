# Set working directory
setwd("C:/Users/Rs1/Goudappel Groep/prj-g-Loopstromenmodel - materiaal loopstromenmodel/code_pok/NVP_analyse")

# Libraries
library(ggplot2)
library(tidyr)
library(dplyr)
library(tidyverse)
library(scales)
library(stringr)
library(minpack.lm)

poi <- "attractiepark"
journey_distance_filter <- 0
tracker_filter <- 0

csv_data <- read.csv(file.path(getwd(), paste0(poi, "_data.csv")), 
                         colClasses = "character", header = TRUE, fileEncoding = "latin1")
csv_data <- subset(csv_data, poi_id != 230)


if (poi == "cultuur") {
  csv_data_extra <- read.csv(
    file.path(getwd(), "bioscoop_data.csv"), 
    colClasses = "character", 
    header = TRUE, 
    fileEncoding = "latin1"
  )
  
  csv_data <- rbind(csv_data, csv_data_extra)
}

if (poi == "sport") {
  csv_data_extra <- read.csv(
    file.path(getwd(), "ijsbaan_data.csv"), 
    colClasses = "character", 
    header = TRUE, 
    fileEncoding = "latin1"
  )
  
  csv_data <- rbind(csv_data, csv_data_extra)
}

# Inlezen en voorbereiden data
output_dir <- file.path(getwd(), "Output", poi)
if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

modal_split <- csv_data %>%
  select(naam, poi_id, station_naam, afstand_poi_station, station_type, aantal_unieke_trackers, journey_distance_gem, aantal_trips,
         starts_with("fractie_"), starts_with("aantal_trips_")) %>%
  rename(ntrips_ongewogen = aantal_trips) %>%
  mutate(ntrips_ongewogen = round(as.numeric(as.character(ntrips_ongewogen)), 0)) %>%
  mutate(across(starts_with("fractie_"), ~as.numeric(as.character(.)))) %>%
  mutate(across(starts_with("aantal_trips_"), ~as.numeric(as.character(.)))) %>%
  mutate(aantal_unieke_trackers = round(as.numeric(as.character(aantal_unieke_trackers)), 0)) %>%
  mutate(journey_distance_gem = round(as.numeric(as.character(journey_distance_gem)), 0)) %>%
 # mutate(afstand_poi_station_org = round(as.numeric(as.character(afstand_poi_station)), 0)) %>%
  mutate(afstand_poi_station = round(as.numeric(as.character(afstand_poi_station))*1.63, 0)) %>% #CORRECTIEFACTOR OP HEMELSBREDE AFSTAND
  mutate(type_station = case_when(
    grepl("stop", station_type, ignore.case = TRUE) ~ "stop",
    grepl("intercity", station_type, ignore.case = TRUE) ~ "intercity",
    grepl("facultatief", station_type, ignore.case = TRUE) ~ "facultatief",
    TRUE ~ NA_character_
  ))

modal_split = subset(modal_split, journey_distance_gem > journey_distance_filter & aantal_unieke_trackers > tracker_filter) # Filteren data

# -------- LONG DF 1: FRACTIES --------
modal_split_long_frac <- modal_split %>%
  select(naam, poi_id, station_naam, afstand_poi_station, type_station, aantal_trips_gewogen,
         matches("^fractie_(lopen|fiets|btm|trein|auto)_gewogen$")) %>%
  pivot_longer(
    cols = starts_with("fractie_"),
    names_to = "vervoermiddel",
    values_to = "fractie"
  ) %>%
  mutate(
    vervoermiddel = str_replace(vervoermiddel, "fractie_", ""),
    vervoermiddel = str_replace(vervoermiddel, "_gewogen", ""),
    naam_afstand = paste0(naam, ", ", afstand_poi_station)
  )

# -------- LONG DF 2: AANTALLEN TRIPS --------
modal_split_long_trips <- modal_split %>%
  select(naam,  poi_id, station_naam, afstand_poi_station, ntrips_ongewogen,
         matches("^aantal_trips_(lopen|fiets|btm|trein|auto)_gewogen$")) %>%
  pivot_longer(
    cols = starts_with("aantal_trips_"),
    names_to = "vervoermiddel",
    values_to = "aantal_trips"
  ) %>%
  mutate(
    vervoermiddel = str_replace(vervoermiddel, "aantal_trips_", ""),
    vervoermiddel = str_replace(vervoermiddel, "_gewogen", ""),
    afstand_bin = cut(afstand_poi_station,
                     breaks = c(0, 500, 1000, 2000, 3000, 5000, 50000),
                     include.lowest = TRUE, right = FALSE,
                     labels = c("0–500", "500–1000", "1000–2000", "2000–3000", "3000–5000", "5000–50000"))
  )

# -------- GRAFIEK 1: Modal split per locatie --------
modal_split_long_frac$naam_afstand <- factor(modal_split_long_frac$naam_afstand,
                                             levels = modal_split_long_frac %>%
                                               distinct(naam_afstand, afstand_poi_station) %>%
                                               arrange(afstand_poi_station) %>%
                                               pull(naam_afstand))

train_labels <- modal_split_long_frac %>% filter(vervoermiddel == "trein")

p1 <- ggplot(modal_split_long_frac, aes(x = naam_afstand, y = fractie, fill = vervoermiddel)) +
  geom_bar(stat = "identity") +
  geom_text(data = train_labels, aes(label = percent(fractie, accuracy = 1)),
            vjust = -0.5, size = 2, color = "black") +
  labs(
    title = paste("Modal split per POI geordend op afstand tot station -", poi),
    x =  paste(poi, "- hemelsbrede afstand station in meters"), y = "Aandeel", fill = "Vervoermiddel"
  ) +
  scale_fill_manual(values = c(
    "trein" = "#FB61D7", "btm" = "#F8766D", "auto" = "#00B6EB",
    "fiets" = "#C49A00", "lopen" = "#A58AFF"
  )) +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 90, hjust = 1))

p1

#ggsave(filename = file.path(output_dir, paste0("1a_modal_split_per_poi_", tracker_filter, "_", journey_distance_filter,".jpg")), plot = p1, width = 8, height = 6, dpi = 300)

# -------- GRAFIEK 2: Scatter afstand vs trein aandeel --------
p2 <- ggplot(filter(modal_split_long_frac, vervoermiddel == "trein"),
       aes(x = afstand_poi_station, y = fractie, color = type_station)) +
  geom_point() +
  scale_color_brewer(palette = "Set1") +
  labs(
    title = paste("Afstand tot station vs aandeel trein -", poi),
    x = "Afstand tot station (meter)", y = "Aandeel trein", color = "Type station"
  ) +
  scale_x_continuous(labels = label_comma()) +
  theme_minimal()

p2

#ggsave(filename = file.path(output_dir, paste0("2a_scatter_aandeel_trein_", tracker_filter, "_", journey_distance_filter,".jpg")), plot = p2, width = 8, height = 6, dpi = 300)

# -------- GRAFIEK 3: Modal split per afstandsklasse --------
modal_bins_summary <- modal_split_long_trips %>%
  group_by(afstand_bin, vervoermiddel) %>%
  summarise(totaal_trips = sum(aantal_trips, na.rm = TRUE), 
            totaal_trips_ongewogen = sum(ntrips_ongewogen, na.rm = TRUE),
            .groups = "drop") %>%
  group_by(afstand_bin) %>%
  mutate(totaal = sum(totaal_trips),
         aandeel = totaal_trips / totaal) %>%
  ungroup()

frequentie_poi <- modal_split_long_trips %>%
  group_by(afstand_bin) %>%
  summarise(frequentie = n_distinct(naam), .groups = "drop")

modal_bins_summary <- left_join(modal_bins_summary, frequentie_poi, by = "afstand_bin")

modal_bins_summary <- modal_bins_summary %>%
  mutate(frequentie_totaal_label = paste0("pois=", frequentie, "\n n=", totaal_trips_ongewogen))

p3 <- ggplot(modal_bins_summary, aes(x = factor(afstand_bin), y = aandeel, fill = vervoermiddel)) +
  geom_bar(stat = "identity") +
  geom_text(aes(label = frequentie_totaal_label, y = 0.97), vjust = 0, hjust = 0.5, size = 3, angle = 0) +
  labs(
    title = paste0("Modal split per afstandsklasse - ", poi),
    x = "Afstandsklassen (meters)", y = "Aandeel met de trein", fill = "Vervoermiddel"
  ) +
  scale_fill_manual(values = c(
    "trein" = "#FB61D7", "btm" = "#F8766D", "auto" = "#00C094",
    "fiets" = "#C49A00", "lopen" = "#A58AFF"
  )) +
  theme_minimal()  +
  theme(axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.25)) +
  geom_text(
    data = subset(modal_bins_summary, vervoermiddel == "trein"),
    aes(label = scales::percent(aandeel, accuracy = 1)),
    position = position_stack(vjust = 0.5),
    color = "black", size = 3
  ) 

p3
#ggsave(filename = file.path(output_dir, paste0("3a_modal_split_per_afstandsklasse_corr_", tracker_filter, "_", journey_distance_filter,".jpg")), plot = p3, width = 8, height = 6, dpi = 300)

# -------- GRAFIEK 4: Functie schatten --------

#Functie schatten door midden afstandsklassen 
# fractie_trein_per_afstandsklasse <- subset(modal_bins_summary, vervoermiddel == "trein")
# fractie_trein_per_afstandsklasse <- fractie_trein_per_afstandsklasse %>%
#   group_by(afstand_bin) %>%
#   mutate(
#     afstand_bin = str_replace_all(afstand_bin, "–", "-")  # Vervang en-dash door gewoon koppelteken
#   ) %>%
#   separate(afstand_bin, into = c("min_afstand", "max_afstand"), sep = "-") %>%
#   mutate(
#     min_afstand = as.numeric(min_afstand),
#     max_afstand = as.numeric(max_afstand),
#     x = (min_afstand + max_afstand) / 2000
#   ) %>%
#   ungroup()
# 
# x <- fractie_trein_per_afstandsklasse$x #/ 1000
# y_trein <- fractie_trein_per_afstandsklasse$aandeel
# 
# model_gaussian_bins <- nlsLM(
#   y_trein ~ gaussian(x, a, c),
#   start = list(a = 0.08, c = 2)#,
#   #weights = gewichten 
# )
# summary_model_gaussian_bins <- capture.output(summary(model_gaussian_bins))
# writeLines(summary_model_gaussian_bins, paste0(output_dir, "/4a_functie_fractie_trein_bins_cor_", poi, ".txt") )
# 
# 
# x_fit <- seq(min(x), max(x), length.out = 200)
# y_fit <- predict(model_gaussian_bins, list(x = x_fit))
# fit_bins <- data.frame(x = x_fit, y = y_fit)
# coefs_bins <- coef(model_gaussian_bins)
# a_bins <- round(as.numeric(coefs_bins["a"]),3)
# c_bins <- round(as.numeric(coefs_bins["c"]),2)
# formule_fit_bins <- paste0("y == ", a_bins, " * exp(-x^2 / (2 * (", c_bins, ")^2))")
# formule_fit_bins <- parse(text = formule_fit_bins)

#Functie schatten door pois
fractie_trein_per_poi  <- subset(modal_split_long_frac, vervoermiddel == "trein")
fractie_trein_per_poi$x <- fractie_trein_per_poi$afstand_poi_station / 1000
fractie_trein_per_poi$aandeel <- fractie_trein_per_poi$fractie
fractie_trein_per_poi$gewicht <- fractie_trein_per_poi$aantal_trips_gewogen

x <- fractie_trein_per_poi$x #/ 1000
y_trein <- fractie_trein_per_poi$aandeel
gewichten <- fractie_trein_per_poi$gewicht

model_gaussian_pois_gewogen <- nlsLM(
  y_trein ~ gaussian(x, a, c),
  start = list(a = 0.08, c = 2),
  weights = fractie_trein_per_poi$gewicht
)
summary_model_gaussian_pois_gewogen <- capture.output(summary(model_gaussian_pois_gewogen))
writeLines(summary_model_gaussian_pois_gewogen, paste0(output_dir, "/4a_functie_fractie_trein_pois_cor_", poi, ".txt") )

x_fit <- seq(min(x), max(x), length.out = 200)
y_fit <- predict(model_gaussian_pois_gewogen, list(x = x_fit))
fit_pois <- data.frame(x = x_fit, y = y_fit)
coefs_pois <- coef(model_gaussian_pois_gewogen)
a_pois <- round(as.numeric(coefs_pois["a"]),3)
c_pois <- round(as.numeric(coefs_pois["c"]),2)
formule_fit_pois <- paste0("y == ", a_pois, " * exp(-x^2 / (2 * (", c_pois, ")^2))")
formule_fit_pois <- parse(text = formule_fit_pois)

# Bepalen onder/bovengrens binomiaal
x_vals <- seq(min(x), max(x), length.out = 200)
y_vals <- a_pois * exp(-x_vals^2 / (2 * c_pois^2)) #rondom pois fit
n <- 50 #elk punt n waarnemingen
sd_vals <- sqrt(y_vals * (1 - y_vals) / n) #binomiale variantie en standaarddeviatie
upper <- pmin(y_vals + 2 * sd_vals, 1) #bereken boven- en ondergrens, binnen [0, 1]
lower <- pmax(y_vals - 2 * sd_vals, 0) #bereken boven- en ondergrens, binnen [0, 1]
lijn_df <- data.frame(x = x_vals, pred = y_vals, upper = upper, lower = lower)

# Maken grafiek
p4 <- ggplot(fractie_trein_per_afstandsklasse, aes(x = x, y = aandeel)) +
  geom_point(color = "#FB61D7", size = 3, shape = 18) + 
  geom_point(data = fractie_trein_per_poi, aes(x = x, y = aandeel, color = gewicht), 
             , size = 3)  +
  scale_color_gradient(low = "azure", high = "azure4") +
  geom_text(data = fractie_trein_per_poi,
              aes(x = x, y = aandeel, label = poi_id),
              vjust = -0.5, size = 2) +
  #geom_line(data = fit_bins, aes(x = x, y = y), color = "#FB61D7", size = 1) +
  #annotate("text", x = 2, y = 0.09, label = formule_fit_bins, parse = TRUE, color = "#FB61D7", hjust = 0)+
  geom_line(data = fit_pois, aes(x = x, y = y), color = "grey", size = 1) +
  annotate("text", x = 2, y = 0.08, label = formule_fit_pois, parse = TRUE, color = "grey", hjust = 0)+
  geom_ribbon(data = lijn_df, aes(x = x, ymin = lower, ymax = upper), 
              fill = "grey", alpha = 0.1, inherit.aes = FALSE) +
  labs(
    title = paste0("Fractie trein per afstandsklasse - ", poi), #" (aantal trackers >", tracker_filter, " & gem journey distance < ", journey_distance_filter, ")"),
    x = "midden van afstandsklasse (km)", y = "Fractie trein"
  ) +
  scale_x_continuous(limits = c(0, 5)) +
  coord_cartesian(ylim = c(0, 0.1)) + #voor attractiepark op 0.12
  theme_minimal()

p4

#ggsave(filename = file.path(output_dir, paste0("4a_functie_fitting_aandeel_trein_corr.jpg")), plot = p4, width = 8, height = 6, dpi = 300)


