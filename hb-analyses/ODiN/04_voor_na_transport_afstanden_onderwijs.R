create_histogram <- function(df, numeric_col, title, save_csv = TRUE, save_plot = TRUE, output_dir = getwd(), file_format = "png", binwidth = 0.5) {
  
  # Maak de bins aan en sla de labels op
  df <- df %>%
    mutate(bin = cut(!!sym(numeric_col), 
                     breaks = seq(floor(min(df[[numeric_col]])), ceiling(max(df[[numeric_col]])), by = binwidth), 
                     include.lowest = TRUE, 
                     right = FALSE))  # Het interval is [a, b)
  
  # Maak het histogram
  histogram <- ggplot(df, aes(x = bin)) +
    geom_bar(fill = "darkblue", color = "black", alpha = 1) +
    ggtitle(title) +
    theme_minimal() +
    theme(
      axis.title.x = element_text(size = 12),
      axis.title.y = element_text(size = 12),
      plot.title = element_text(hjust = 0.5),
      axis.text.x = element_text(hjust = 1, vjust = -0.01, angle = 90)  # Eventueel labels roteren
    ) +
    scale_x_discrete(labels = function(x) gsub(",", "-", x))  # Vervang de komma door een streepje
  
  # Optioneel: Opslaan als afbeelding
  if (save_plot) {
    img_filename <- paste0(output_dir, "/", title, "_histogram.", file_format)
    ggsave(img_filename, plot = histogram, width = 6, height = 6, dpi = 300)
    message("Afbeelding opgeslagen als: ", img_filename)
  }
  
  # Optioneel: Opslaan als CSV van de binned data (aantal observaties per bin)
  if (save_csv) {
    df_histogram <- df %>%
      count(bin) 
    
    csv_filename <- paste0(output_dir, "/", title, "_histogram_data.csv")
    write.csv(df_histogram, csv_filename, row.names = FALSE)
    message("CSV opgeslagen als: ", csv_filename)
  }
  
  return(histogram)  # Toon het histogram in R
}

create_histogram_overlay <- function(df, numeric_col, title, subset_df = NULL, subset_title = "Subset", 
                             save_csv = TRUE, save_plot = TRUE, output_dir = getwd(), 
                             file_format = "png", binwidth = 0.5) {
  
  # Controleer of df een data.frame of tibble is
  if (!is.data.frame(df)) {
    stop("De input 'df' moet een data.frame of tibble zijn.")
  }
  
  # Controleer of numeric_col bestaat in de data
  if (!numeric_col %in% colnames(df)) {
    stop(paste("De kolom", numeric_col, "bestaat niet in de dataframe."))
  }
  
  # Controleer of de kolom numeriek is
  if (!is.numeric(df[[numeric_col]])) {
    stop(paste("De kolom", numeric_col, "moet numeriek zijn."))
  }
  
  # Maak de bins aan voor de volledige data
  df <- df %>%
    mutate(bin = cut(!!sym(numeric_col), 
                     breaks = seq(floor(min(df[[numeric_col]])), ceiling(max(df[[numeric_col]])), by = binwidth), 
                     include.lowest = TRUE, 
                     right = FALSE))
  
  # Als een subset wordt meegegeven, controleer het formaat en maak de bins
  if (!is.null(subset_df)) {
    if (!is.data.frame(subset_df)) {
      stop("De input 'subset_df' moet een data.frame of tibble zijn.")
    }
    if (!numeric_col %in% colnames(subset_df)) {
      stop(paste("De kolom", numeric_col, "bestaat niet in de subset dataframe."))
    }
    subset_df <- subset_df %>%
      mutate(bin = cut(!!sym(numeric_col), 
                       breaks = seq(floor(min(df[[numeric_col]])), ceiling(max(df[[numeric_col]])), by = binwidth), 
                       include.lowest = TRUE, 
                       right = FALSE))
  }
  
  # Maak het basis histogram
  histogram <- ggplot(df, aes(x = bin)) +
    geom_bar(fill = "darkblue", color = "black", alpha = 1, aes(y = ..count..), position = "identity") +
    ggtitle(title) +
    theme_minimal() +
    theme(
      axis.title.x = element_text(size = 12),
      axis.title.y = element_text(size = 12),
      plot.title = element_text(hjust = 0.5),
      axis.text.x = element_text(hjust = 1, vjust = -0.01, angle = 90)
    ) +
    scale_x_discrete(labels = function(x) gsub(",", "-", x))
  
  # Voeg een tweede histogram toe als subset_df niet NULL is
  if (!is.null(subset_df)) {
    histogram <- histogram +
      geom_bar(data = subset_df, aes(x = bin, y = ..count..), 
               fill = "skyblue", color = "black", alpha = 1, position = "identity") +
      labs(subtitle = paste0("Overlay met subset: ", subset_title))
  }
  
  # Optioneel: Opslaan als afbeelding
  if (save_plot) {
    img_filename <- paste0(output_dir, "/", title, "_histogram.", file_format)
    ggsave(img_filename, plot = histogram, width = 6, height = 6, dpi = 300)
    message("Afbeelding opgeslagen als: ", img_filename)
  }
  
  # Optioneel: Opslaan als CSV van de binned data
  if (save_csv) {
    df_histogram <- df %>%
      count(bin) 
    
    csv_filename <- paste0(output_dir, "/", title, "_histogram_data.csv")
    write.csv(df_histogram, csv_filename, row.names = FALSE)
    message("CSV opgeslagen als: ", csv_filename)
    
    if (!is.null(subset_df)) {
      subset_histogram <- subset_df %>%
        count(bin)
      subset_csv_filename <- paste0(output_dir, "/", title, "_subset_histogram_data.csv")
      write.csv(subset_histogram, subset_csv_filename, row.names = FALSE)
      message("Subset CSV opgeslagen als: ", subset_csv_filename)
    }
  }
  
  return(histogram)
}


create_histogram_overlay(subset(data_onderwijs_trein,!is.na(voor_natransport_van_of_naar_onderwijs_afstand)), 
                 "voor_natransport_van_of_naar_onderwijs_afstand", 
                 "odin_voornatransport_van_of_naar_onderwijs_afstand_totaal_overlay", 
                 subset(data_onderwijs_trein, !is.na(voor_natransport_van_of_naar_onderwijs_afstand)&lopen_van_of_naar_onderwijs==1),
                 "loopritten_van_of_naar_onderwijs_afstand",
                 save_csv = TRUE, 
                 save_plot = TRUE, 
                 output_dir = file.path(getwd(), "output", "ODiN", "4_voor_na_transport_afstanden"), 
                 file_format = "jpg")


create_histogram(subset(data_onderwijs_trein, !is.na(voor_natransport_van_of_naar_onderwijs_afstand)), "voor_natransport_van_of_naar_onderwijs_afstand", "odin_voornatransport_van_of_naar_onderwijs_afstand_totaal", save_csv = TRUE, save_plot = TRUE, output_dir = file.path(getwd(), "output", "ODiN", "4_voor_na_transport_afstanden"), file_format = "jpg")
create_histogram(subset(data_onderwijs_trein_heen, !is.na(voor_natransport_van_of_naar_onderwijs_afstand)), "voor_natransport_van_of_naar_onderwijs_afstand", "odin_voornatransport_van_of_naar_onderwijs_afstand_heen", save_csv = TRUE, save_plot = TRUE, output_dir = file.path(getwd(), "output", "ODiN", "4_voor_na_transport_afstanden"), file_format = "jpg")
create_histogram(subset(data_onderwijs_trein_terug, !is.na(voor_natransport_van_of_naar_onderwijs_afstand)), "voor_natransport_van_of_naar_onderwijs_afstand", "odin_voornatransport_van_of_naar_onderwijs_afstand_terug", save_csv = TRUE, save_plot = TRUE, output_dir = file.path(getwd(), "output", "ODiN", "4_voor_na_transport_afstanden"), file_format = "jpg")

gemiddelde_loopafstand_totaal = mean(subset(data_onderwijs_trein$voor_natransport_van_of_naar_onderwijs_afstand, !is.na(data_onderwijs_trein$voor_natransport_van_of_naar_onderwijs_afstand)))


## per afstandsbin: aandeel lopen
