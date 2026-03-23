### MODAL SPLIT ONDERWIJS TOTAAL ###

create_pie_chart <- function(df, category_col, title, save_csv = TRUE, save_plot = TRUE, output_dir = getwd(), file_format = "png") {
  # Bereken de frequentie en percentages
  df_pie <- df %>%
    count(across(all_of(category_col))) %>%
    mutate(percentage = round(n / sum(n) * 100, 1),
           label = paste0(percentage, "%"))  # Labels maken
  
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
    geom_text(aes(label = label), position = position_stack(vjust = 0.5)) +
    theme_void() +
    ggtitle(title)
  
  # Optioneel: Opslaan als afbeelding
  if (save_plot) {
    img_filename <- paste0(output_dir, "/", title, "_pie_chart.", file_format)
    ggsave(img_filename, plot = pie_chart, width = 6, height = 6, dpi = 300)
    message("Afbeelding opgeslagen als: ", img_filename)
  }
  
  return(pie_chart)  # Toon het diagram in R
}

# Modal split onderwijs totaal
create_pie_chart(data_onderwijs, "KHvm", "odin_modal_split_onderwijs_totaal", save_csv = TRUE, save_plot = TRUE, output_dir = file.path(getwd(), "output", "ODiN", "1_modal_split"), file_format = "jpg")
create_pie_chart(data_onderwijs_heen, "KHvm", "odin_modal_split_onderwijs_heen", save_csv = TRUE, save_plot = TRUE, output_dir = file.path(getwd(), "output", "ODiN", "1_modal_split"), file_format = "jpg")
create_pie_chart(data_onderwijs_terug, "KHvm", "odin_modal_split_onderwijs_terug", save_csv = TRUE, save_plot = TRUE, output_dir = file.path(getwd(), "output", "ODiN", "1_modal_split"), file_format = "jpg")
