# maken van deze bins: 0-0.2, 0.2-0.4, 0.4-0.6, 0.6-0.8, 0.8-1.2, 1.2-1.8, > 1.8
# dataframe met: bin, aantal verplaatsingen in bin, aantal loopverplaatsingen in bin, 
# aantal bus/tram/metro verplaatsingen in bin, aantal fietsverplaatsingen in bin, aantal NA in bin, aantal auto in bin
# aandeel loopverplaatsingen in bin, aandeel bus/tram/metro verplaatsingen in bin, aandeel fietsverplaatsingen in bin, aandeel auto in bin
# aandeel gedeeld door binwidth

voor_na_transport_bins = subset(data_onderwijs_trein, 
                                select = c("OPID", 
                                           "voor_natransport_van_of_naar_onderwijs2", 
                                           "voor_natransport_van_of_naar_onderwijs_afstand"))
colnames(voor_na_transport_bins) = c("OPID","voor_na_transport","afstand")
voor_na_transport_bins = na.omit(voor_na_transport_bins)

voor_na_transport_bins = voor_na_transport_bins %>%
  mutate(bins = cut(afstand, breaks = c(0,0.2,0.4,0.6,0.8,1,1.2,1.4,1.6,2.4,3.2,5,7,75), include.lowest = TRUE, right = FALSE)) 
  #mutate(bins = cut(afstand, breaks = c(0,0.2,0.4,0.6,0.8,1.2,1.8,40), include.lowest = TRUE)) 
  #mutate(bins = cut(afstand, breaks = seq(0,40,by=0.5), include.lowest = TRUE)) 
  #mutate(bins = cut(afstand, breaks = c(seq(0,10,by=0.2),40), include.lowest = TRUE)) 
  #mutate(bins = cut(afstand, breaks = c(seq(0,5,by=0.1),40), include.lowest = TRUE)) 
  #mutate(bins = cut(afstand, breaks = seq(0,40,by=0.5), include.lowest = TRUE, right = FALSE )) 
  #mutate(bins = cut(afstand, breaks = c(seq(0,10,by=0.2),40), include.lowest = TRUE, right = FALSE )) 
  #mutate(bins = cut(afstand, breaks = c(seq(0,5,by=0.1),40), include.lowest = TRUE, right = FALSE )) 
  
voor_na_transport_bins <- voor_na_transport_bins %>%
  group_by(bins) %>%
  summarise(
    frequentie = n(),
    te_voet = sum(voor_na_transport == "Te voet"),
    fiets = sum(voor_na_transport == "Fiets"),
    BTM = sum(voor_na_transport == "Bus/tram/metro"),
    auto = sum(voor_na_transport %in% c("Personenauto - passagier", "Personenauto - bestuurder")),
    overig = sum(voor_na_transport == "Overig"),
    te_voet_frac = round(te_voet / frequentie, 3),
    fiets_frac = round(fiets / frequentie, 3),
    BTM_frac = round(BTM / frequentie, 3),
    auto_frac = round(auto / frequentie, 3),
    overig_frac = round(overig / frequentie, 3),
    midden_bin = bins %>% 
      unique() %>% 
      str_remove_all("\\[|\\)|\\(|\\]") %>%  # Verwijder ALLE haakjes correct
      str_split_fixed(",", 2) %>%
      as.numeric() %>%
      mean(na.rm = TRUE) %>%
      round(3),
    .groups = "drop"
  )

# Data in lang formaat zetten voor ggplot
voor_na_transport_bins_long <- voor_na_transport_bins %>%
  select(bins, te_voet_frac, fiets_frac, BTM_frac, auto_frac, overig_frac) %>%
  pivot_longer(cols = -bins, names_to = "vervoermiddel", values_to = "aandeel")

voor_na_transport_bins_long <- merge(voor_na_transport_bins_long, subset(voor_na_transport_bins, select = c("bins","frequentie")), by = "bins", all.x = TRUE)

# Maak de stacked bar chart
ggplot(voor_na_transport_bins_long, aes(x = factor(bins), y = aandeel, fill = vervoermiddel)) +
  geom_bar(stat = "identity") +
  labs(
    title = "Modal split per bin",
    subtitle = "station-onderwijs en onderwijs-station",
    x = "Opgegeven afstand tussen statione en onderwijs (km)",
    y = "Aandeel per modaliteit",
    fill = "Vervoersmiddel"
  ) +
  scale_fill_manual(
    values = c("te_voet_frac" = "#A58AFF", 
               "fiets_frac" = "#C49A00", 
               "BTM_frac" = "#F8766D", 
               "auto_frac" = "#00B6EB", 
               "overig_frac" = "#53B400")
  ) +
  theme_minimal() +
  theme(axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.25)) +  # Draai labels 90 graden
  geom_text(
    aes(label = frequentie, y = 1.02),  # Gebruik de frequentie kolom voor de labels
    vjust = 0.2,             # Positie boven de staaf
    size = 3,                  # Tekstgrootte
    angle = 90
  )

ggsave(file.path(getwd(), "output", "ODiN", "5_voor_na_transport_bins", "modal_split_per_bin2.jpg"), width = 8, height = 6, dpi = 300)
write.csv(voor_na_transport_bins, file.path(getwd(), "output", "ODiN", "5_voor_na_transport_bins", "modal_split_per_bin2.csv"), row.names = FALSE)




