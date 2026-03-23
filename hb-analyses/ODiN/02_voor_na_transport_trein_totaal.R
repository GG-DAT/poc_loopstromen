### VOOR-NATRANSPORT TREIN ONDERWIJS ###

create_bar_chart <- function(df, category_col, title, save_csv = TRUE, save_plot = TRUE, output_dir = getwd(), file_format = "png") {
  # Bereken de frequentie en percentages
  df_bar <- df %>%
    count(across(all_of(category_col))) %>%
    mutate(percentage = round(n / sum(n) * 100, 1))  # Percentage berekenen
  
  # Optioneel: Opslaan als CSV
  if (save_csv) {
    csv_filename <- paste0(output_dir, "/", title, "_tabel.csv")
    write.csv(df_bar, csv_filename, row.names = FALSE)
    message("CSV opgeslagen als: ", csv_filename)
  }
  
  # Maak het staafdiagram
  bar_chart <- ggplot(df_bar, aes(x = !!sym(category_col), y = n, fill = !!sym(category_col))) +
    geom_bar(stat = "identity", color = "white") +
    geom_text(aes(label = paste0(percentage, "%")), 
              #vjust = -0.5, 
              angle = 90,  # Draai de percentages 90 graden
              size = 3) +  # Maak de tekst kleiner
    theme_minimal() +
    ggtitle(title) +
    xlab(category_col) +
    ylab("Frequentie") +
    theme(legend.position = "none", 
          axis.text.x = element_text(angle = 90, hjust = 1, vjust = 0.5))  # Draai de x-as labels
  
  # Optioneel: Opslaan als afbeelding
  if (save_plot) {
    img_filename <- paste0(output_dir, "/", title, "_bar_chart.", file_format)
    ggsave(img_filename, plot = bar_chart, width = 8, height = 6, dpi = 300)
    message("Afbeelding opgeslagen als: ", img_filename)
  }
  
  return(bar_chart)  # Toon het diagram in R
}

create_pie_chart <- function(df, category_col, title, save_csv = TRUE, save_plot = TRUE, output_dir = getwd(), file_format = "png", custom_colors = NULL) {
  # Standaardkleuren instellen
  default_colors <- c(
    "Bus/tram/metro" = "#F8766D",      
    "Fiets" = "#C49A00",                
    "Overig" = "#53B400",              
    "Personenauto - bestuurder" = "#00C094", 
    "Personenauto - passagier" = "#00B6EB",  
    "Te voet" = "#A58AFF",              
    "Trein" = "#FB61D7",               
    "NA" = "grey"
  )
  
  # Gebruik standaardkleuren tenzij custom_colors is opgegeven
  if (is.null(custom_colors)) {
    custom_colors <- default_colors
  }
  
  # Bereken de frequentie en percentages
  df_pie <- df %>%
    count(across(all_of(category_col))) %>%
    mutate(percentage = round(n / sum(n) * 100, 1),
           label = paste0(percentage, "%"))  # Labels maken
  
  # Verwijder categorieën met percentage kleiner dan 0.5
  df_pie <- df_pie %>%
    filter(percentage >= 0.5)
  
  # Optioneel: Opslaan als CSV
  if (save_csv) {
    csv_filename <- paste0(output_dir, "/", title, "_tabel.csv")
    write.csv(df_pie, csv_filename, row.names = FALSE)
    message("CSV opgeslagen als: ", csv_filename)
  }
  
  # Maak het cirkeldiagram
  pie_chart <- ggplot(df_pie, aes(x = "", y = n, fill = !!sym(category_col))) +
    geom_bar(stat = "identity", width = 1, color = "white") +
    coord_polar(theta = "y") +
    geom_text(aes(label = label), position = position_stack(vjust = 0.5), size = 3) +
    theme_void() +
    ggtitle(title) +
    scale_fill_manual(values = custom_colors)  # Pas kleuren toe
  
  # Optioneel: Opslaan als afbeelding
  if (save_plot) {
    img_filename <- paste0(output_dir, "/", title, "_pie_chart.", file_format)
    ggsave(img_filename, plot = pie_chart, width = 6, height = 6, dpi = 300)
    message("Afbeelding opgeslagen als: ", img_filename)
  }
  
  return(pie_chart)  # Toon het diagram in R
}

# Verdeling voor/natransport trein onderwijs
data_onderwijs_trein = subset(data_onderwijs, Hvm == "Trein")

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

unique(data_onderwijs_trein$voor_natransport_van_of_naar_onderwijs2)

data_onderwijs_trein_heen = subset(data_onderwijs_trein, Doel == "Onderwijs/cursus volgen")
data_onderwijs_trein_terug = subset(data_onderwijs_trein, Doel == "Naar huis")

create_bar_chart(data_onderwijs_trein, "voor_natransport_van_of_naar_onderwijs2", "odin_voor_na_transport_trein_totaal2", save_csv = TRUE, save_plot = TRUE, output_dir = file.path(getwd(), "output", "ODiN", "2_voor_na_transport"), file_format = "jpg")
create_bar_chart(data_onderwijs_trein_heen, "voor_natransport_van_of_naar_onderwijs2", "odin_voor_na_transport_trein_heen2", save_csv = TRUE, save_plot = TRUE, output_dir = file.path(getwd(), "output", "ODiN", "2_voor_na_transport"), file_format = "jpg")
create_bar_chart(data_onderwijs_trein_terug, "voor_natransport_van_of_naar_onderwijs2", "odin_voor_na_transport_trein_terug2", save_csv = TRUE, save_plot = TRUE, output_dir = file.path(getwd(), "output", "ODiN", "2_voor_na_transport"), file_format = "jpg")

create_pie_chart(data_onderwijs_trein, "voor_natransport_van_of_naar_onderwijs2", "odin_voor_na_transport_trein_totaal2", save_csv = FALSE, save_plot = TRUE, output_dir = file.path(getwd(), "output", "ODiN", "2_voor_na_transport"), file_format = "jpg")
create_pie_chart(data_onderwijs_trein_heen, "voor_natransport_van_of_naar_onderwijs2", "odin_voor_na_transport_trein_heen2", save_csv = FALSE, save_plot = TRUE, output_dir = file.path(getwd(), "output", "ODiN", "2_voor_na_transport"), file_format = "jpg")
create_pie_chart(data_onderwijs_trein_terug, "voor_natransport_van_of_naar_onderwijs2", "odin_voor_na_transport_trein_terug2", save_csv = FALSE, save_plot = TRUE, output_dir = file.path(getwd(), "output", "ODiN", "2_voor_na_transport"), file_format = "jpg")


#create_bar_chart(data_onderwijs_trein, "voor_natransport_van_of_naar_onderwijs", "ovin_voor_na_transport_trein_totaal", save_csv = TRUE, save_plot = TRUE, output_dir = file.path(getwd(), "output", "OViN", "voor_na_transport"), file_format = "jpg")
#create_bar_chart(data_onderwijs_trein_heen, "voor_natransport_van_of_naar_onderwijs", "ovin_voor_na_transport_trein_heen", save_csv = TRUE, save_plot = TRUE, output_dir = file.path(getwd(), "output", "OViN", "voor_na_transport"), file_format = "jpg")
#create_bar_chart(data_onderwijs_trein_terug, "voor_natransport_van_of_naar_onderwijs", "ovin_voor_na_transport_trein_terug", save_csv = TRUE, save_plot = TRUE, output_dir = file.path(getwd(), "output", "OViN", "voor_na_transport"), file_format = "jpg")

#create_pie_chart(data_onderwijs_trein, "voor_natransport_van_of_naar_onderwijs", "ovin_voor_na_transport_trein_totaal", save_csv = FALSE, save_plot = TRUE, output_dir = file.path(getwd(), "output", "OViN", "voor_na_transport"), file_format = "jpg")
#create_pie_chart(data_onderwijs_trein_heen, "voor_natransport_van_of_naar_onderwijs", "ovin_voor_na_transport_trein_heen", save_csv = FALSE, save_plot = TRUE, output_dir = file.path(getwd(), "output", "OViN", "voor_na_transport"), file_format = "jpg")
#create_pie_chart(data_onderwijs_trein_terug, "voor_natransport_van_of_naar_onderwijs", "ovin_voor_na_transport_trein_terug", save_csv = FALSE, save_plot = TRUE, output_dir = file.path(getwd(), "output", "OViN", "voor_na_transport"), file_format = "jpg")

#create_bar_chart(data_onderwijs_trein, "voor_natransport_van_of_naar_onderwijs", "voor_na_transport_trein_totaal", save_csv = TRUE, save_plot = TRUE, output_dir = file.path(getwd(), "output", "OViN_ODiN", "voor_na_transport"), file_format = "jpg")
#create_bar_chart(data_onderwijs_trein_heen, "voor_natransport_van_of_naar_onderwijs", "voor_na_transport_trein_heen", save_csv = TRUE, save_plot = TRUE, output_dir = file.path(getwd(), "output", "OViN_ODiN", "voor_na_transport"), file_format = "jpg")
#create_bar_chart(data_onderwijs_trein_terug, "voor_natransport_van_of_naar_onderwijs", "voor_na_transport_trein_terug", save_csv = TRUE, save_plot = TRUE, output_dir = file.path(getwd(), "output", "OViN_ODiN", "voor_na_transport"), file_format = "jpg")

#create_pie_chart(data_onderwijs_trein, "voor_natransport_van_of_naar_onderwijs", "voor_na_transport_trein_totaal", save_csv = FALSE, save_plot = TRUE, output_dir = file.path(getwd(), "output", "OViN_ODiN", "voor_na_transport"), file_format = "jpg")
#create_pie_chart(data_onderwijs_trein_heen, "voor_natransport_van_of_naar_onderwijs", "voor_na_transport_trein_heen", save_csv = FALSE, save_plot = TRUE, output_dir = file.path(getwd(), "output", "OViN_ODiN", "voor_na_transport"), file_format = "jpg")
#create_pie_chart(data_onderwijs_trein_terug, "voor_natransport_van_of_naar_onderwijs", "voor_na_transport_trein_terug", save_csv = FALSE, save_plot = TRUE, output_dir = file.path(getwd(), "output", "OViN_ODiN", "voor_na_transport"), file_format = "jpg")

#voor_na_transport_na = subset(data_onderwijs_trein, is.na(voor_natransport_van_of_naar_onderwijs))



