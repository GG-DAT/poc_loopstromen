# Data (x, y)
png(file.path(getwd(), "output", "ODiN", "10_modal_split_functies", "geschatte_functie_trein_gaussian.png"), width = 800, height = 600)
x <- modal_split_bins$midden_bin
y_trein <- modal_split_bins$trein_frac

# Plot de originele gegevens (scatter plot)
plot(x, y_trein, main = "Fractie trein naar afstand", xlab = "afstand station - onderwijs (km)", ylab = "aandeel met trein", pch = 19, col = "#FB61D7")

# Model gaussian
gaussian <- function(x, a, c) {
  a * exp(-((x)^2) / (2 * c^2))
}
model_gaussian <- nls(y_trein ~ gaussian(x, a, c), 
                      start = list(a = 2, c = 10))
summary(model_gaussian)

# Fit tekenen
x_fit <- seq(min(x), max(x), length.out = 200)
y_fit <- predict(model_gaussian, list(x = x_fit))
lines(x_fit, y_fit, col = "#FB61D7", lwd = 2)

# Parameterwaarden ophalen 2
coefs <- coef(model_gaussian)
a <- round(coefs["a"],3)
c <- round(coefs["c"],3)

text(x = 5, y = 0.2,
     labels = paste0("y = ", a, " * exp(-x^2 / (2 * (", c, ")^2))"),
     pos = 4, cex = 1)

dev.off()  # Sluit het grafisch apparaat en sla het bestand op

output_dir <- file.path(getwd(), "Output/ODiN/10_modal_split_functies")
summary_model_gaussian <- capture.output(summary(model_gaussian))
writeLines(summary_model_gaussian, paste0(output_dir, "/functie_fractie_trein_onderwijs.txt") )
