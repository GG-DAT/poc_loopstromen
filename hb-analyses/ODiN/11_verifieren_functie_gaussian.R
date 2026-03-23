
#Bepalen fractie_trein per onderwijslocatie combi
modal_split_bins_analyse = modal_split_bins_data %>%
  group_by(onderwijslocatie) %>%
  summarise(
    frequentie = n(),
    trein = sum(modaliteit == "Trein"),
    trein_frac = round(trein / frequentie, 3),
    gewogen_afstand_station = max(gewogen_afstand_station),
    inuit = max(inuit),
    onderwijstypes = max(onderwijstypes),
    station_naam = paste(unique(station_naam), collapse = ", "),
    .groups = "drop"
  )
#modal_split_bins_analyse <- modal_split_bins_analyse[!modal_split_bins_analyse$onderwijsstation == '0', ]

universiteiten = c("Utrecht", "Leiden", "Maastricht", "Eindhoven", "Enschede", "Delft", "Groningen", "Amsterdam", "Rotterdam", "Nijmegen", "Tilburg")
regex_universiteiten <- paste(universiteiten, collapse = "|")
modal_split_bins_analyse$universiteit <- ifelse(
  grepl(regex_universiteiten, modal_split_bins_analyse$station_naam)&
    modal_split_bins_analyse$onderwijstypes %in% c("ho", "ho,mbo"),
  "universiteit",
  "geen universiteit"
)
modal_split_bins_analyse$universiteit2 <- ifelse(
  grepl(regex_universiteiten, modal_split_bins_analyse$station_naam),
  "universiteit",
  "geen universiteit"
)

modal_split_bins_analyse_freqentie100 = subset(modal_split_bins_analyse, frequentie >100) #29
modal_split_bins_analyse_freqentie50 = subset(modal_split_bins_analyse, frequentie >50) #56
modal_split_bins_analyse_freqentie25 = subset(modal_split_bins_analyse, frequentie >25) #105
modal_split_bins_analyse_freqentie10 = subset(modal_split_bins_analyse, frequentie >10) #240

#Geschatte functie
x_vals <- seq(min(modal_split_bins_analyse$gewogen_afstand_station),
              max(modal_split_bins_analyse$gewogen_afstand_station),
              length.out = 1000)
#y_vals <- 0.383 * x_vals^(-0.022) * exp(-0.157 * x_vals)
#y_vals <- 0.372 * x_vals^(-0.086) * exp(-0.245 * x_vals)
y_vals <- 0.287 * exp(-x_vals^2 / (2* (4.082)^2)) #GAUSSIAN

lijn_df <- data.frame(gewogen_afstand_station = x_vals, trein_frac = y_vals)

#2x SD obv binomiaal
n <- 50
sd_vals <- sqrt(y_vals * (1 - y_vals) / n)
upper <- y_vals + 2 * sd_vals
lower <- y_vals - 2 * sd_vals
upper <- pmin(upper, 1)
lower <- pmax(lower, 0)
lijn_df$upper <- upper
lijn_df$lower <- lower

#Plotten afstand/frac_trein per onderwijsinstelling tov geschatte functie
plot <- ggplot(modal_split_bins_analyse_freqentie50, aes(x = gewogen_afstand_station, y = trein_frac, color = as.factor(onderwijstypes))) +
  geom_point() +  
  scale_color_brewer(palette = "Set1") +
  labs(
    title = "Scatterplot afstand station-onderwijs tov aandeel studenten dat met de trein komt",
    x = "afstand station - onderwijs (km)",
    y = "aandeel met trein",
    color = "Onderwijstype"
  )  +
  xlim(0,5) +
  geom_line(data = lijn_df, aes(x = gewogen_afstand_station, y = trein_frac),
            inherit.aes = FALSE, color = "black", size = 1.2, linetype = "dashed")  +
  geom_ribbon(data = lijn_df, aes(x = gewogen_afstand_station, ymin = lower, ymax = upper),
              inherit.aes = FALSE, fill = "blue", alpha = 0.1) +
  theme_minimal()

plot
ggsave(file.path(getwd(), "output", "ODiN", "11_verifieren_functie", "scatterplot_afstand_aandeel_onderwijstypes_gaussian.jpg"), width = 8, height = 6, dpi = 300)

plot <- ggplot(modal_split_bins_analyse_freqentie50, aes(x = gewogen_afstand_station, y = trein_frac, color = as.numeric(frequentie))) +
  geom_point() +  
  scale_color_viridis_c(direction = -1) +
  labs(
    title = "Scatterplot afstand station-onderwijs tov aandeel studenten dat met de trein komt",
    x = "afstand station - onderwijs (km)",
    y = "aandeel met trein",
    color = "aantal verplaatsingen"
  )  +
  xlim(0,5) +
  geom_line(data = lijn_df, aes(x = gewogen_afstand_station, y = trein_frac),
            inherit.aes = FALSE, color = "black", size = 1.2, linetype = "dashed") +
  geom_ribbon(data = lijn_df, aes(x = gewogen_afstand_station, ymin = lower, ymax = upper),
              inherit.aes = FALSE, fill = "blue", alpha = 0.1) +
  theme_minimal()

plot
ggsave(file.path(getwd(), "output", "ODiN", "11_verifieren_functie", "scatterplot_afstand_aandeel_inuit_gaussian.jpg"), width = 8, height = 6, dpi = 300)



plot <- ggplot(modal_split_bins_analyse_freqentie50, aes(x = gewogen_afstand_station, y = trein_frac, color = as.factor(onderwijstypes))) +
  geom_point() +  
  scale_color_brewer(palette = "Set1") +
  labs(
    title = "Scatterplot afstand station-onderwijs tov aandeel studenten dat met de trein komt",
    x = "afstand station - onderwijs (km)",
    y = "aandeel met trein",
    color = "Onderwijstype"
  )  +
  xlim(0,5) +
  geom_line(data = lijn_df, aes(x = gewogen_afstand_station, y = trein_frac),
            inherit.aes = FALSE, color = "black", size = 1.2, linetype = "dashed")  +
  geom_ribbon(data = lijn_df, aes(x = gewogen_afstand_station, ymin = lower, ymax = upper),
              inherit.aes = FALSE, fill = "blue", alpha = 0.1) +
  geom_text(
    data = modal_split_bins_analyse_freqentie50,
    aes(label = station_naam),
    check_overlap = TRUE,  # voorkomt overlap
    vjust = -1,            # iets boven de punten
    size = 2,
    inherit.aes = TRUE
  ) +
  theme_minimal()

plot
ggsave(file.path(getwd(), "output", "ODiN", "11_verifieren_functie", "scatterplot_afstand_aandeel_onderwijstypes_tekst_gaussian.jpg"), width = 8, height = 6, dpi = 300)

plot <- ggplot(modal_split_bins_analyse_freqentie50, aes(x = gewogen_afstand_station, y = trein_frac, color = as.numeric(inuit))) +
  geom_point() +  
  scale_color_viridis_c(direction = -1) +
  labs(
    title = "Scatterplot afstand station-onderwijs tov aandeel studenten dat met de trein komt",
    x = "afstand station - onderwijs (km)",
    y = "aandeel met trein",
    color = "aantal inuitstappers"
  )   +
  xlim(0,5) +
  geom_line(data = lijn_df, aes(x = gewogen_afstand_station, y = trein_frac),
            inherit.aes = FALSE, color = "black", size = 1.2, linetype = "dashed") +
  geom_ribbon(data = lijn_df, aes(x = gewogen_afstand_station, ymin = lower, ymax = upper),
              inherit.aes = FALSE, fill = "blue", alpha = 0.1) +
  theme_minimal()

plot
ggsave(file.path(getwd(), "output", "ODiN", "11_verifieren_functie", "scatterplot_afstand_aandeel_inuit_gaussian.jpg"), width = 8, height = 6, dpi = 300)

plot <- ggplot(modal_split_bins_analyse_freqentie50, aes(x = gewogen_afstand_station, y = trein_frac, color = as.numeric(frequentie))) +
  geom_point() +  
  scale_color_viridis_c(direction = -1) +
  labs(
    title = "Scatterplot afstand station-onderwijs tov aandeel studenten dat met de trein komt",
    x = "afstand station - onderwijs (km)",
    y = "aandeel met trein",
    color = "aantal verplaatsingen"
  )  +
  xlim(0,5) +
  geom_line(data = lijn_df, aes(x = gewogen_afstand_station, y = trein_frac),
            inherit.aes = FALSE, color = "black", size = 1.2, linetype = "dashed") +
  geom_ribbon(data = lijn_df, aes(x = gewogen_afstand_station, ymin = lower, ymax = upper),
              inherit.aes = FALSE, fill = "blue", alpha = 0.1) +
  theme_minimal()

plot
ggsave(file.path(getwd(), "output", "ODiN", "11_verifieren_functie", "scatterplot_afstand_aandeel_frequentie_gaussian.jpg"), width = 8, height = 6, dpi = 300)


plot <- ggplot(modal_split_bins_analyse_freqentie50, aes(x = gewogen_afstand_station, y = trein_frac, color = as.numeric(frequentie))) +
  geom_point() +  
  scale_color_viridis_c(direction = -1) +
  labs(
    title = "Scatterplot afstand station-onderwijs tov aandeel studenten dat met de trein komt",
    x = "afstand station - onderwijs (km)",
    y = "aandeel met trein",
    color = "aantal verplaatsingen"
  )  +
  geom_line(data = lijn_df, aes(x = gewogen_afstand_station, y = trein_frac),
            inherit.aes = FALSE, color = "black", size = 1.2, linetype = "dashed") +
  geom_ribbon(data = lijn_df, aes(x = gewogen_afstand_station, ymin = lower, ymax = upper),
              inherit.aes = FALSE, fill = "blue", alpha = 0.1) +
  theme_minimal()

plot
ggsave(file.path(getwd(), "output", "ODiN", "11_verifieren_functie", "scatterplot_afstand_aandeel_frequentie_volledig_bereik_gaussian.jpg"), width = 8, height = 6, dpi = 300)


plot <- ggplot(modal_split_bins_analyse, aes(x = gewogen_afstand_station, y = trein_frac, color = as.numeric(frequentie))) +
  geom_point() +  
  scale_color_viridis_c(direction = -1) +
  labs(
    title = "Scatterplot afstand station-onderwijs tov aandeel studenten dat met de trein komt",
    x = "afstand station - onderwijs (km)",
    y = "aandeel met trein",
    color = "aantal verplaatsingen"
  )  +
  xlim(0,5) +
  geom_line(data = lijn_df, aes(x = gewogen_afstand_station, y = trein_frac),
            inherit.aes = FALSE, color = "black", size = 1.2, linetype = "dashed") +
  #geom_ribbon(data = lijn_df, aes(x = gewogen_afstand_station, ymin = lower, ymax = upper),
  #            inherit.aes = FALSE, fill = "blue", alpha = 0.1) +
  theme_minimal()

plot
ggsave(file.path(getwd(), "output", "ODiN", "11_verifieren_functie", "scatterplot_afstand_aandeel_frequentie_alle_punten_guassian.jpg"), width = 8, height = 6, dpi = 300)


plot <- ggplot(modal_split_bins_analyse, aes(x = gewogen_afstand_station, y = trein_frac, color = as.numeric(frequentie))) +
  geom_point() +  
  scale_color_viridis_c(direction = -1) +
  labs(
    title = "Scatterplot afstand station-onderwijs tov aandeel studenten dat met de trein komt",
    x = "afstand station - onderwijs (km)",
    y = "aandeel met trein",
    color = "aantal verplaatsingen"
  )  +
  geom_line(data = lijn_df, aes(x = gewogen_afstand_station, y = trein_frac),
            inherit.aes = FALSE, color = "black", size = 1.2, linetype = "dashed") +
  #geom_ribbon(data = lijn_df, aes(x = gewogen_afstand_station, ymin = lower, ymax = upper),
  #            inherit.aes = FALSE, fill = "blue", alpha = 0.1) +
  theme_minimal()

plot
ggsave(file.path(getwd(), "output", "ODiN", "11_verifieren_functie", "scatterplot_afstand_aandeel_frequentie_volledig_bereik_alle_punten_guassian.jpg"), width = 8, height = 6, dpi = 300)
# 
# ### AFWIJKING MBO/HO tov functie ###
# analyse_mbo_ho = modal_split_bins_analyse 
# analyse_mbo_ho$trein_frac_functie = 0.372 * analyse_mbo_ho$gewogen_afstand_station^(0.086) * exp(-0.245 * analyse_mbo_ho$gewogen_afstand_station)
# #analyse_mbo_ho$trein_frac_functie = 0.353 * analyse_mbo_ho$gewogen_afstand_station^(0.047) * exp(-0.208 * analyse_mbo_ho$gewogen_afstand_station)
# #analyse_mbo_ho$trein_frac_functie = 0.383 * analyse_mbo_ho$gewogen_afstand_station^(-0.022) * exp(-0.157 * analyse_mbo_ho$gewogen_afstand_station)
# analyse_mbo_ho$verschil_functie = analyse_mbo_ho$trein_frac - analyse_mbo_ho$trein_frac_functie
# analyse_mbo_ho$weegfactor = sqrt(analyse_mbo_ho$frequentie)
# analyse_mbo_ho$verschil_functie_gewogen = analyse_mbo_ho$verschil_functie * analyse_mbo_ho$weegfactor
# 
# analyse_mbo_ho_alles <- analyse_mbo_ho %>%
#   group_by(onderwijstypes) %>%
#   summarise(
#     afwijking_tov_schatting = sum(verschil_functie_gewogen) / sum(weegfactor),
#     sd_afwijking = sqrt(sum(weegfactor*verschil_functie**2) / sum(weegfactor)),
#     BI_afwijking = 2 * (sd_afwijking / sqrt(n)),
#     aantal_onderwijsinstellingen = n(),
#     totale_frequentie = sum(frequentie),
#     .groups = "drop"
#   )
# 
# analyse_mbo_ho_freq1 <- subset(analyse_mbo_ho, frequentie > 1) %>%
#   group_by(onderwijstypes) %>%
#   summarise(
#     afwijking_tov_schatting = sum(verschil_functie_gewogen) / sum(weegfactor),
#     sd_afwijking = sqrt(sum(weegfactor*verschil_functie**2) / sum(weegfactor)),
#     BI_afwijking = 2 * (sd_afwijking / sqrt(n)),
#     aantal_onderwijsinstellingen = n(),
#     totale_frequentie = sum(frequentie),
#     .groups = "drop"
#   )
# 
# analyse_mbo_ho_freq10 <- subset(analyse_mbo_ho, frequentie > 10) %>%
#   group_by(onderwijstypes) %>%
#   summarise(
#     afwijking_tov_schatting = sum(verschil_functie_gewogen) / sum(weegfactor),
#     sd_afwijking = sqrt(sum(weegfactor*verschil_functie**2) / sum(weegfactor)),
#     BI_afwijking = 2 * (sd_afwijking / sqrt(n)),
#     aantal_onderwijsinstellingen = n(),
#     totale_frequentie = sum(frequentie),
#     .groups = "drop"
#   )
# 
# analyse_mbo_ho_freq50 <- subset(analyse_mbo_ho, frequentie > 50) %>%
#   group_by(onderwijstypes) %>%
#   summarise(
#     afwijking_tov_schatting = sum(verschil_functie_gewogen) / sum(weegfactor),
#     sd_afwijking = sqrt(sum(weegfactor*verschil_functie**2) / sum(weegfactor)),
#     BI_afwijking = 2* (sd_afwijking / sqrt(n)),
#     aantal_onderwijsinstellingen = n(),
#     totale_frequentie = sum(frequentie),
#     .groups = "drop"
#   )
# 
# analyse_universiteit_alles <- analyse_mbo_ho %>%
#   group_by(universiteit2) %>%
#   summarise(
#     afwijking_tov_schatting = sum(verschil_functie_gewogen) / sum(weegfactor),
#     sd_afwijking = sqrt(sum(weegfactor*verschil_functie**2) / sum(weegfactor)),
#     BI_afwijking = 2* (sd_afwijking / sqrt(n)),
#     aantal_onderwijsinstellingen = n(),
#     totale_frequentie = sum(frequentie),
#     .groups = "drop"
#   )

