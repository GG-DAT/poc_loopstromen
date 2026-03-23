# Verdeling loopafstanden
data_onderwijs_trein_lopen = subset(data_onderwijs_trein, lopen_van_of_naar_onderwijs == 1)
data_onderwijs_trein_lopen_heen = subset(data_onderwijs_trein_heen, lopen_van_of_naar_onderwijs == 1)
data_onderwijs_trein_lopen_terug = subset(data_onderwijs_trein_terug, lopen_van_of_naar_onderwijs == 1)

create_histogram <- function(df, numeric_col, title, save_csv = TRUE, save_plot = TRUE, output_dir = getwd(), file_format = "png", binwidth = 0.5) {
  
  # Maak de bins aan en sla de labels op
  df <- df %>%
    mutate(bin = cut(!!sym(numeric_col), 
                     breaks = seq(floor(min(df[[numeric_col]])), ceiling(max(df[[numeric_col]])), by = binwidth), 
                     include.lowest = TRUE, 
                     right = FALSE))  # Het interval is [a, b)
  
  # Maak het histogram
  histogram <- ggplot(df, aes(x = bin)) +
    geom_bar(fill = "skyblue", color = "black", alpha = 1) +
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

#create_histogram(data_onderwijs_trein_lopen, "loopafstand", "ovin_loopafstand_totaal", save_csv = TRUE, save_plot = TRUE, output_dir = file.path(getwd(), "output", "OViN", "loopafstanden"), file_format = "jpg")
#create_histogram(data_onderwijs_trein_lopen_heen, "loopafstand", "ovin_loopafstand_heen", save_csv = TRUE, save_plot = TRUE, output_dir = file.path(getwd(), "output", "OViN", "loopafstanden"), file_format = "jpg")
#create_histogram(data_onderwijs_trein_lopen_terug, "loopafstand", "ovin_loopafstand_terug", save_csv = TRUE, save_plot = TRUE, output_dir = file.path(getwd(), "output", "OViN", "loopafstanden"), file_format = "jpg")

#create_histogram(data_onderwijs_trein_lopen, "loopafstand", "loopafstand_totaal", save_csv = TRUE, save_plot = TRUE, output_dir = file.path(getwd(), "output", "OViN_ODiN", "loopafstanden"), file_format = "jpg")
#create_histogram(data_onderwijs_trein_lopen_heen, "loopafstand", "loopafstand_heen", save_csv = TRUE, save_plot = TRUE, output_dir = file.path(getwd(), "output", "OViN_ODiN", "loopafstanden"), file_format = "jpg")
#create_histogram(data_onderwijs_trein_lopen_terug, "loopafstand", "loopafstand_terug", save_csv = TRUE, save_plot = TRUE, output_dir = file.path(getwd(), "output", "OViN_ODiN", "loopafstanden"), file_format = "jpg")

create_histogram(data_onderwijs_trein_lopen, "loopafstand", "odin_loopafstand_totaal", save_csv = TRUE, save_plot = TRUE, output_dir = file.path(getwd(), "output", "ODiN", "3_loopafstanden"), file_format = "jpg")
create_histogram(data_onderwijs_trein_lopen_heen, "loopafstand", "odin_loopafstand_heen", save_csv = TRUE, save_plot = TRUE, output_dir = file.path(getwd(), "output", "ODiN", "3_loopafstanden"), file_format = "jpg")
create_histogram(data_onderwijs_trein_lopen_terug, "loopafstand", "odin_loopafstand_terug", save_csv = TRUE, save_plot = TRUE, output_dir = file.path(getwd(), "output", "ODiN", "3_loopafstanden"), file_format = "jpg")


gemiddelde_loopafstand_totaal = mean(data_onderwijs_trein_lopen$loopafstand)
