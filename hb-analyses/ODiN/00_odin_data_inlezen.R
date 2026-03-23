#installeer packages
if(!require(haven)) {install.packages('haven')} # load/save .sav document (spss)
if(!require(tidyverse)) {install.packages('tidyverse')} # databewerking
if(!require(dplyr)) {install.packages('dplyr')} # 
if(!require(ggplot2)) {install.packages('ggplot2')} # 
if(!require(ggrepel)) {install.packages('ggrepel')} # 

#werkmap
setwd("C:/Users/Rs1/Goudappel Groep/prj-g-Loopstromenmodel - materiaal loopstromenmodel/code_pok/ODiN_analyse")

#laad data
odin_data_2018_2023 <- haven::read_sav("F:/BGO/4. Data/ODIN/2018-2023/ODiN_2018-2023_Databestand.sav")

#selecteren benodigde variabelen
data_odin <- subset(odin_data_2018_2023, 
  select = c('OP',
           'OPID',
           'WoGem',
           'WoPC',
           'Opleiding',
           'KLeeft',
           'Verpl',
           'VerplNr',
           'Toer',
           'AantRit',
           'Rit',
           'RitNr',
           'Doel',
           'MotiefV',
           'Hvm',
           'KHvm',
           'Rvm',
           'KRvm',
           'VertPC',
           'AankPC',
           'RVertStat',
           'RAankStat',
           'AfstR',
           'KAfstR',
           'AfstV',
           'KAfstV'
           )
  )

data_odin <- data_odin %>%
  mutate(Hvm = factor(as.numeric(Hvm), levels = 1:24, labels = c(
    "Personenauto", 
    "Trein", 
    "Bus", 
    "Tram", 
    "Metro", 
    "Speedpedelec", 
    "Elektrische fiets", 
    "Niet-elektrische fiets", 
    "Te voet", 
    "Touringcar", 
    "Bestelauto", 
    "Vrachtwagen", 
    "Camper", 
    "Taxi/Taxibusje", 
    "Landbouwvoertuig", 
    "Motor", 
    "Bromfiets", 
    "Snorfiets", 
    "Gehandicaptenvervoermiddel met motor", 
    "Gehandicaptenvervoermiddel zonder motor", 
    "Skates/skeelers/step", 
    "Boot", 
    "Anders met motor", 
    "Anders zonder motor"
  )))

data_odin <- data_odin %>%
  mutate(KHvm = factor(as.numeric(KHvm), levels = 1:7, labels = c(
    "Personenauto - bestuurder",
    "Personenauto - passagier",
    "Trein",
    "Bus/tram/metro",
    "Fiets",
    "Te voet",
    "Overig"
  )))

data_odin <- data_odin %>%
  mutate(KRvm = factor(KRvm, levels = c(1:7, NA), labels = c(
    "Personenauto - bestuurder",
    "Personenauto - passagier",
    "Trein",
    "Bus/tram/metro",
    "Fiets",
    "Te voet",
    "Overig"
  ))) 

data_odin <- data_odin %>%
  mutate(Rvm = factor(Rvm, levels = c(1:24, NA), labels = c(
    "Personenauto",
    "Trein",
    "Bus",
    "Tram",
    "Metro",
    "Speedpedelec",
    "Elektrische fiets",
    "Niet-elektrische fiets",
    "Te voet",
    "Touringcar",
    "Bestelauto",
    "Vrachtwagen",
    "Camper",
    "Taxi/Taxibusje",
    "Landbouwvoertuig",
    "Motor",
    "Bromfiets",
    "Snorfiets",
    "Gehandicaptenvervoermiddel met motor",
    "Gehandicaptenvervoermiddel zonder motor",
    "Skates/skeelers/step",
    "Boot",
    "Anders met motor",
    "Anders zonder motor"
  ))) 

data_odin <- zap_labels(data_odin)
data_odin$bron <- 'odin'
data = data_odin

data <- data %>%
  mutate(Opleiding = factor(as.numeric(Opleiding), levels = 1:8, labels = c(
    "Geen opleiding voltooid",
    "Basisonderwijs, lager onderwijs",
    "Lager beroepsonderwijs of vmbo, vbo, lwoo, vso, vglo, mavo, ulo, mulo",
    "Middelbaar beroepsonderwijs of havo, atheneum, gymnasium, mms, hbs",
    "Hoger beroepsonderwijs, universiteit",
    "Andere opleiding",
    "Onbekend",
    "Niet gevraagd; OP jonger dan 15 jaar"
    
  )))

data <- data %>%
  mutate(KLeeft = factor(as.numeric(KLeeft), levels = 1:18, labels = c(
    "0 t/m 5 jaar",
    "6 t/m 11 jaar",
    "12 t/m 14 jaar",
    "15 t/m 17 jaar",
    "18 t/m 19 jaar",
    "20 t/m 24 jaar",
    "25 t/m 29 jaar",
    "30 t/m 34 jaar",
    "35 t/m 39 jaar",
    "40 t/m 44 jaar",
    "45 t/m 49 jaar",
    "50 t/m 54 jaar",
    "55 t/m 59 jaar",
    "60 t/m 64 jaar",
    "65 t/m 69 jaar",
    "70 t/m 74 jaar",
    "75 t/m 79 jaar",
    "80 jaar of ouder"
    
  )))

data <- data %>%
  mutate(Doel = factor(as.numeric(Doel), levels = 1:14, labels = c(
    "Naar huis",
    "Werken", 
    "Zakelijk bezoek in werksfeer", 
    "Beroepsmatig",
    "Afhalen/brengen personen", 
    "Afhalen/brengen goederen", 
    "Onderwijs/cursus volgen",
    "Winkelen/boodschappen doen", 
    "Visite/logeren", 
    "Toeren/wandelen",
    "Sport/hobby", 
    "Overige vrijetijdsbesteding", 
    "Diensten/persoonlijke verzorging",
    "Ander doel"
  )))

data <- data %>%
  mutate(MotiefV = factor(as.numeric(MotiefV), levels = 1:13, labels = c(
    "Van en naar het werk", 
    "Zakelijk bezoek in werksfeer", 
    "Beroepsmatig",
    "Afhalen/brengen personen", 
    "Afhalen/brengen goederen", 
    "Onderwijs/cursus volgen",
    "Winkelen/boodschappen doen", 
    "Visite/logeren", 
    "Toeren/wandelen",
    "Sport/hobby", 
    "Overige vrijetijdsbesteding", 
    "Diensten/persoonlijke verzorging",
    "Ander motief"
  )))

data <- data %>%
  mutate(KAfstR = factor(KAfstR, levels = c(1:15, NA), labels = c(
    "0,1 tot 0,5 km",
    "0,5 tot 1,0 km",
    "1,0 tot 2,5 km",
    "2,5 tot 3,7 km",
    "3,7 tot 5,0 km",
    "5,0 tot 7,5 km",
    "7,5 tot 10 km",
    "10 tot 15 km",
    "15 tot 20 km",
    "20 tot 30 km",
    "30 tot 40 km",
    "40 tot 50 km",
    "50 km of meer",
    "50 km of meer",
    "50 km of meer"
  ))) 

data <- data %>%
  mutate(KAfstV = factor(KAfstV, levels = c(1:15, NA), labels = c(
    "0,1 tot 0,5 km",
    "0,5 tot 1,0 km",
    "1,0 tot 2,5 km",
    "2,5 tot 3,7 km",
    "3,7 tot 5,0 km",
    "5,0 tot 7,5 km",
    "7,5 tot 10 km",
    "10 tot 15 km",
    "15 tot 20 km",
    "20 tot 30 km",
    "30 tot 40 km",
    "40 tot 50 km",
    "50 km of meer",
    "50 km of meer",
    "50 km of meer"
  )))

#Toevoegen gemeentenaam 
gem_2024 <- read.csv(file.path(getwd(), "Input", "gem_2024.csv"),
                     colClasses = "character", header = TRUE, sep = ';')
pc4_to_gem <- read.csv(file.path(getwd(), "Input", "pc6hnr20240801_gwb.csv"),
                       colClasses = "character", header = TRUE, sep = ',')
pc4_to_gem$pc4 <- substr(pc4_to_gem$PC6, 1, 4)
pc4_to_gem = unique(subset(pc4_to_gem, select = c('pc4', 'Gemeente2024')))
pc4_to_gem = merge(pc4_to_gem, gem_2024, by.x = 'Gemeente2024', by.y = 'Gemeente2024')
pc4_to_gem = subset(pc4_to_gem, select = c('pc4','Gemeentenaam2024'))
pc4_kolom <- table(pc4_to_gem$pc4)
dubbele_waarden <- names(pc4_kolom[pc4_kolom == 2])
te_verwijderen <- logical(nrow(pc4_to_gem))
for (waarde in dubbele_waarden) {
  idx <- which(pc4_to_gem$pc4 == waarde)
  te_verwijderen[idx[2]] <- TRUE
}
pc4_to_gem <- pc4_to_gem[!te_verwijderen, ]
colnames(pc4_to_gem) = c('WoPC',"WoonGemeente")
data = merge(data, pc4_to_gem, by.x = 'WoPC', by.y = 'WoPC')

#selecteren verplaatsingen met als motief onderwijs en leeftijd ouder dan 17
data_onderwijs = subset(data, MotiefV == "Onderwijs/cursus volgen" & !(KLeeft %in% c('0 t/m 5 jaar','6 t/m 11 jaar', '12 t/m 14 jaar'))) #, '15 t/m 17 jaar')))

#1 regel per verplaatsing (per persoon), de informatie van losse ritten wordt samengevoegd
data_onderwijs <- data_onderwijs %>%
  group_by(OPID, VerplNr                                                                                                                                                                                                                                                                                                          ) %>%
  mutate(
    RVertStat = max(RVertStat, na.rm = TRUE),
    RAankStat = max(RAankStat, na.rm = TRUE)
  ) %>%
  summarise(
    across(!c(Verpl, Rvm, KRvm, AfstR, KAfstR), ~ toString(unique(.))),  # Alleen unieke waarden behouden
    across(c(Rvm, KRvm, AfstR, KAfstR), ~ paste(., collapse = ", ")),  # Alle waarden samenvoegen
    .groups = "drop"
  ) %>%
  select(-RitNr, -Rit)

# Functie om voor- en natransport trein te extraheren
extract_transport <- function(KRvm, AfstR) {
  opties <- str_split(KRvm, ",\\s*")[[1]]  # Splits de string op komma's en verwijder spaties
  opties_lower <- str_to_lower(opties)  # Zet alles om naar kleine letters
  afstanden <- as.numeric(str_split(AfstR, ",\\s*")[[1]])  # Zet de afstand-string om in een numerieke vector
  trein_index <- which(opties_lower == "trein")  # Zoek alle indices van 'trein'
  
  # Controleer of 'trein' voorkomt, anders return NA's
  if (length(trein_index) == 0) {
    return(tibble(voortransport = NA, afstand_voortransport = NA, 
                  natransport = NA, afstand_natransport = NA))
  }
  
  # Verzamel alle strings en som van afstanden vóór 'trein' (voortransport), exclusief 'trein'
  if (trein_index[1] > 1) {
    voortransport <- opties[1:(trein_index[1] - 1)]
    afstand_voortransport <- sum(afstanden[1:(trein_index[1] - 1)], na.rm = TRUE)
  } else {
    voortransport <- NA  # Als 'trein' de eerste waarde is, zet voortransport op NA
    afstand_voortransport <- NA
  }
  
  # Verzamel alle strings en som van afstanden ná 'trein' (natransport), exclusief 'trein'
  if (trein_index[length(trein_index)] < length(opties)) {
    natransport <- opties[(trein_index[length(trein_index)] + 1):length(opties)]
    afstand_natransport <- sum(afstanden[(trein_index[length(trein_index)] + 1):length(opties)], na.rm = TRUE)
  } else {
    natransport <- NA  # Als 'trein' de laatste waarde is, zet natransport op NA
    afstand_natransport <- NA
  }
  
  # Maak de output
  return(tibble(
    voortransport = paste(voortransport, collapse = ", "), 
    afstand_voortransport = afstand_voortransport/10,
    natransport = paste(natransport, collapse = ", "), 
    afstand_natransport = afstand_natransport/10
  ))
}

data_onderwijs$bron = "odin"
# Toepassen functie voor-natransport
data_onderwijs <- data_onderwijs %>%
  rowwise() %>%
  mutate(extract = if (bron == "odin" & str_detect(str_to_lower(KRvm), "trein")) list(extract_transport(KRvm, AfstR)) else list(tibble(voortransport = NA, natransport = NA))) %>%
  unnest(extract)

data_onderwijs$voortransport = ifelse(data_onderwijs$bron == "ovin", data_onderwijs$KRvm, data_onderwijs$voortransport)
data_onderwijs$natransport = ifelse(data_onderwijs$bron == "ovin", data_onderwijs$KRvm, data_onderwijs$natransport)

# Bepalen voor- en natransport naar onderwijs en van onderwijs
data_onderwijs$lopen_van_of_naar_onderwijs <- ifelse(
  (data_onderwijs$Doel == "Onderwijs/cursus volgen" & data_onderwijs$natransport == "Te voet") | 
    (data_onderwijs$Doel == "Naar huis" & data_onderwijs$voortransport == "Te voet"), 
  1, 
  NA
)

data_onderwijs$voor_natransport_van_of_naar_onderwijs <- ifelse(
  (data_onderwijs$Doel == "Onderwijs/cursus volgen"), data_onderwijs$natransport, data_onderwijs$voortransport)

data_onderwijs$voor_natransport_van_of_naar_onderwijs_afstand <- ifelse(
  (data_onderwijs$Doel == "Onderwijs/cursus volgen"), data_onderwijs$afstand_natransport, data_onderwijs$afstand_voortransport)


#ophalen code naar stationsnaam
stations_ovin <- read.csv(file.path(getwd(), "Input", "vertstat_aankstat_ovin.csv"), 
                    colClasses = "character", header = FALSE)
colnames(stations_ovin) <- c("code", "stationnaam")

stations_odin <- read.csv(file.path(getwd(), "Input", "vertstat_aankstat.csv"), 
                     colClasses = "character", header = FALSE)
colnames(stations_odin) <- c("code", "stationnaam")

stations = rbind(stations_ovin, stations_odin)
stations = distinct(stations)

#Bepalen of station intercity station is
# intercity_stations <- read.csv(file.path(getwd(), "Input", "intercity_stations.csv"),
#                                colClasses = "character", header = FALSE)
# stations$stationtype <- ifelse(stations$stationnaam %in% (intercity_stations$V1), 'intercity', 'sprinter')

#Toevoegen naam stations
orig_col_order <- colnames(data_onderwijs)

data_onderwijs <- merge(data_onderwijs, stations[, c("code", "stationnaam")], 
                        by.x = "RVertStat", by.y = "code", all.x = TRUE)
colnames(data_onderwijs)[ncol(data_onderwijs)] <- "VertrekStation"

data_onderwijs <- merge(data_onderwijs, stations[, c("code", "stationnaam")], 
                        by.x = "RAankStat", by.y = "code", all.x = TRUE)
colnames(data_onderwijs)[ncol(data_onderwijs)] <- "AankomstStation"

new_cols <- setdiff(colnames(data_onderwijs), orig_col_order)
final_col_order <- c(orig_col_order, new_cols)

data_onderwijs <- data_onderwijs[, final_col_order]

# Bepalen Onderwijs postcode
data_onderwijs$onderwijslocatie = ifelse(
  (data_onderwijs$Doel == "Onderwijs/cursus volgen"), data_onderwijs$AankPC, data_onderwijs$VertPC)

# Bepalen Onderwijs station
data_onderwijs$onderwijsstation = ifelse(
  (data_onderwijs$Doel == "Onderwijs/cursus volgen"), data_onderwijs$AankomstStation, data_onderwijs$VertrekStation)

# Bepalen Onderwijs loopafstand
data_onderwijs$loopafstand <- sapply(1:nrow(data_onderwijs), function(i) {
  AfstR <- data_onderwijs$AfstR[i]  # Haal de AfstR voor de rij
  afstanden <- as.numeric(strsplit(AfstR, ",")[[1]])  # Splits de string in een vector
  
  # Controleer eerst of natransport of voortransport niet NA is
  if (!is.na(data_onderwijs$natransport[i]) && data_onderwijs$natransport[i] == "Te voet") {
    return(afstanden[length(afstanden)]/10)  # Laatste afstand als natransport "Te voet" is
  } else if (!is.na(data_onderwijs$voortransport[i]) && data_onderwijs$voortransport[i] == "Te voet") {
    return(afstanden[1]/10)  # Eerste afstand als voortransport "Te voet" is
  } else {
    return(NA)  # Als geen van beide condities waar is, return NA
  }
})

# Aparte datasets voor heen & terug 
data_onderwijs_heen = subset(data_onderwijs, Doel == "Onderwijs/cursus volgen")
data_onderwijs_terug = subset(data_onderwijs, Doel == "Naar huis")

# Verdeling voor/natransport trein onderwijs
data_onderwijs_trein = subset(data_onderwijs, grepl("Trein", KRvm))

data_onderwijs_trein$voor_natransport_van_of_naar_onderwijs2 <- ifelse(grepl("Bus/tram/metro", data_onderwijs_trein$voor_natransport_van_of_naar_onderwijs), 
                                                                       "Bus/tram/metro", 
                                                                       ifelse(grepl("Personenauto - passagier", data_onderwijs_trein$voor_natransport_van_of_naar_onderwijs), 
                                                                              "Personenauto - passagier", 
                                                                              ifelse(grepl("Personenauto - bestuurder", data_onderwijs_trein$voor_natransport_van_of_naar_onderwijs), 
                                                                                     "Personenauto - bestuurder", 
                                                                                     ifelse(grepl("Fiets", data_onderwijs_trein$voor_natransport_van_of_naar_onderwijs), 
                                                                                            "Fiets", 
                                                                                            ifelse(grepl("Overig", data_onderwijs_trein$voor_natransport_van_of_naar_onderwijs), 
                                                                                                   "Overig", 
                                                                                                   data_onderwijs_trein$voor_natransport_van_of_naar_onderwijs)))))


data_onderwijs_trein_heen = subset(data_onderwijs_trein, Doel == "Onderwijs/cursus volgen")
data_onderwijs_trein_terug = subset(data_onderwijs_trein, Doel == "Naar huis")



