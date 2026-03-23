### AANTALLEN PER PC4 ###

aantallen_per_onderwijslocatie <- data_onderwijs %>%
  group_by(onderwijslocatie) %>%
  summarise(
    aantal_verplaatsingen = n(),
    aantal_respondenten = n_distinct(OPID),
    #aantal_verplaatsingen_trein = sum(Hvm == "Trein"),
    aantal_verplaatsingen_trein = sum(grepl("Trein", Rvm)),
    
    #aantal_verplaatsingen_heen = sum(Doel == "Onderwijs/cursus volgen"),
    #aantal_verplaatsingen_terug = sum(Doel == "Naar huis"),
    #aantal_respondenten_heen = n_distinct(OPID[Doel == "Onderwijs/cursus volgen"]),
   # aantal_respondenten_terug = n_distinct(OPID[Doel == "Naar huis"]),
    .groups = "drop"
  )


loopstations <- subset(data_onderwijs, lopen_van_of_naar_onderwijs ==1) %>%
  group_by(onderwijslocatie) %>%
  summarise(
    aantal_trein_voet = n(),
    gemiddelde_loopafstand = round(sum(loopafstand)/n(), digits = 2),
    maximale_loopafstand = max(loopafstand),
    minimale_loopafstand = min(loopafstand),
    across(onderwijsstation, ~ toString(unique(.))),  # Alleen unieke waarden behouden
    #stations = list(unique(na.omit(onderwijsstation[lopen_van_of_naar_onderwijs == 1]))),  # NA verwijderen
    .groups = "drop"
  )

aantallen_per_onderwijslocatie <- merge(aantallen_per_onderwijslocatie, loopstations, by.x = "onderwijslocatie", by.y = "onderwijslocatie", all.x = TRUE)
aantallen_per_onderwijslocatie <- aantallen_per_onderwijslocatie[aantallen_per_onderwijslocatie$onderwijslocatie != '0000', ]
aantallen_per_onderwijslocatie <- aantallen_per_onderwijslocatie[aantallen_per_onderwijslocatie$onderwijslocatie != '0', ]
aantallen_per_onderwijslocatie$aandeel_voet = aantallen_per_onderwijslocatie$aantal_trein_voet / aantallen_per_onderwijslocatie$aantal_verplaatsingen
aantallen_per_onderwijslocatie <- aantallen_per_onderwijslocatie[order(aantallen_per_onderwijslocatie$aantal_verplaatsingen, decreasing = TRUE),]

write.csv(aantallen_per_onderwijslocatie, file.path(getwd(), "output", "ODiN", "aantallen_per_onderwijslocatie.csv"), row.names = FALSE)

aantallen_per_onderwijslocatie <- aantallen_per_onderwijslocatie[!is.na(aantallen_per_onderwijslocatie$aantal_trein_voet), ]
write.csv(aantallen_per_onderwijslocatie, file.path(getwd(), "output", "ODiN", "aantallen_per_onderwijslocatie_trein_voet.csv"), row.names = FALSE)


#write.csv(aantallen_per_onderwijslocatie, file.path(getwd(), "output", "OViN_ODiN", "aantallen_per_onderwijslocatie_ovin.csv"), row.names = FALSE)
#write.csv(aantallen_per_onderwijslocatie, file.path(getwd(), "output", "OViN_ODiN", "aantallen_per_onderwijslocatie_ovin_odin.csv"), row.names = FALSE)
#write.csv(aantallen_per_onderwijslocatie, file.path(getwd(), "output", "ODiN", "aantallen_per_onderwijslocatie_incl_15_17.csv"), row.names = FALSE)
