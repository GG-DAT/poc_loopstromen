# Selecteren alle onderwijsritten
modal_split_bins = subset(data_onderwijs, 
                                select = c("OPID",
                                           "WoonGemeente",
                                           "KHvm", 
                                           "onderwijslocatie")) #19539
colnames(modal_split_bins) = c("OPID","WoonGemeente","modaliteit","onderwijslocatie")
modal_split_bins = modal_split_bins[!modal_split_bins$onderwijslocatie == '0', ] #19467
modal_split_bins = modal_split_bins[!modal_split_bins$onderwijslocatie == '0000', ] #19054

# Koppelen afstanden
afstand_station_per_onderwijsinstelling <- read.csv(file.path(getwd(), "Input", "pc4_odin_subset_incl_15_17.csv"), colClasses = "character", header = TRUE)
#afstand_station_per_onderwijsinstelling <- read.csv(file.path(getwd(), "Input", "pc4_odin_subset.csv"), colClasses = "character", header = TRUE)
afstand_station_per_onderwijsinstelling = subset(afstand_station_per_onderwijsinstelling, select = c("onderwijslocatie","station_naam", "gewogen_afstand_station","inuit","onderwijstypes"))
afstand_station_per_onderwijsinstelling$gewogen_afstand_station = as.numeric(afstand_station_per_onderwijsinstelling$gewogen_afstand_station) /1000
colnames(pc4_to_gem) = c('onderwijslocatie',"OnderwijsGemeente")
afstand_station_per_onderwijsinstelling = merge(afstand_station_per_onderwijsinstelling, pc4_to_gem, by.x = 'onderwijslocatie', by.y = 'onderwijslocatie')
modal_split_bins = merge(modal_split_bins, afstand_station_per_onderwijsinstelling, by.x = "onderwijslocatie" , by.y = "onderwijslocatie", all.x = TRUE)
modal_split_bins$gewogen_afstand_station = modal_split_bins$gewogen_afstand_station * 1.63
modal_split_bins = na.omit(modal_split_bins) #13999
modal_split_bins$zelfde_gemeente = ifelse(modal_split_bins$WoonGemeente == modal_split_bins$OnderwijsGemeente, 1, 0)

modal_split_bins_data = modal_split_bins

# Aantal gewenste bins
modal_split_bins = modal_split_bins %>%
  mutate(afstand = as.numeric(as.character(gewogen_afstand_station))) %>%
  #mutate(bins = cut(afstand, breaks = c(0,0.5,1,1.5,2,2.7,3.6,4.8,8.5,10,25,41), include.lowest = TRUE, right = FALSE)) 
  #mutate(bins = cut(afstand, breaks = seq(0,40,by=0.5), include.lowest = TRUE)) 
  #mutate(bins = cut(afstand, breaks = seq(0,40,by=2), include.lowest = TRUE)) 
  #mutate(bins = cut(afstand, breaks = c(0,0.5,1,1.5,2,2.7,3.6,4.8,8.5,41), include.lowest = TRUE, right = FALSE)) 
  mutate(bins = cut(afstand, breaks = c(0,0.5,1,1.5,2,2.7,3.6,4.8,8.5,10,17,25,41), include.lowest = TRUE, right = FALSE)) 

modal_split_bins <- modal_split_bins %>%
  group_by(bins) %>%
  summarise(
    frequentie = n(),
    trein = sum(modaliteit == "Trein"),
    te_voet = sum(modaliteit == "Te voet"),
    fiets = sum(modaliteit == "Fiets"),
    BTM = sum(modaliteit == "Bus/tram/metro"),
    auto = sum(modaliteit == "Personenauto - bestuurder"),
    auto_passagier = sum(modaliteit== "Personenauto - passagier"),
    overig = sum(modaliteit == "Overig"),
    trein_frac = round(trein/ frequentie, 3),
    te_voet_frac = round(te_voet / frequentie, 3),
    fiets_frac = round(fiets / frequentie, 3),
    BTM_frac = round(BTM / frequentie, 3),
    auto_frac = round(auto / frequentie, 3),
    auto_passagier_frac = round(auto_passagier / frequentie, 3),
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

#modal_split_bins2 = modal_split_bins
  
# Data in lang formaat zetten voor ggplot
modal_split_bins_long <- modal_split_bins %>%
  select(bins, trein_frac, te_voet_frac, fiets_frac, BTM_frac, auto_frac, auto_passagier_frac, overig_frac) %>%
  pivot_longer(cols = -bins, names_to = "vervoermiddel", values_to = "aandeel")

modal_split_bins_long <- merge(modal_split_bins_long, subset(modal_split_bins, select = c("bins","frequentie")), by = "bins", all.x = TRUE)

# Maak de stacked bar chart
ggplot(modal_split_bins_long, aes(x = factor(bins), y = aandeel, fill = vervoermiddel)) +
  geom_bar(stat = "identity") +
  labs(
    title = "Modal split per bin",
    subtitle = "verplaatsingen van/naar onderwijs postcodes met ook onderwijslocatie in Spectrum",
    x = "Afstand station onderwijs (km)",
    y = "Aandeel",
    fill = "Vervoersmiddel"
  ) +
  scale_fill_manual(
    values = c("trein_frac" = "#FB61D7", 
               "te_voet_frac" = "#A58AFF", 
               "fiets_frac" = "#C49A00", 
               "BTM_frac" = "#F8766D", 
               "auto_frac" = "#00C094",  
               "auto_passagier_frac" = "#00B6EB",  
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

ggsave(file.path(getwd(), "output", "ODiN", "9_modal_split_station_onderwijs_binning", "modal_split_per_bin2.jpg"), width = 8, height = 6, dpi = 300)
write.csv(modal_split_bins, file.path(getwd(), "output", "ODiN", "9_modal_split_station_onderwijs_binning", "modal_split_per_bin2.csv"), row.names = FALSE)



