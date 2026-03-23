# Data (x, y)
png(file.path(getwd(), "output", "ODiN", "6_voor_na_transport_functies", "geschatte_functies_voor_na_transport_nieuw.png"), width = 800, height = 600)
x <- voor_na_transport_bins$midden_bin
y_voet <- voor_na_transport_bins$te_voet_frac  # simulatie van een Gaussian + ruis
y_btm <- voor_na_transport_bins$BTM_frac
y_fiets <- voor_na_transport_bins$fiets_frac

# Plot de originele gegevens (scatter plot)
plot(x, y_voet, main = "Fractie voor/natransport lopen naar afstand", xlab = "afstand station - onderwijs", ylab = "aandeel te voet", pch = 19, xlim = c(0, 10), col = "#A58AFF")
#points(x, y_btm, col = "#F8766D", pch = 19)
#points(x, y_fiets, col = "#C49A00", pch = 19)

# Definieer de functie / het model
gaussian <- function(x, c) {
  1 * exp(-((x - 0)^2) / (2 * c^2))
}
#fit_voet <- nls(y_voet ~ gaussian(x, a, b c), start = list(a = 10, b = 0, c = 1))

fit_voet <- nls(y_voet ~ gaussian(x, c), start = list(c = 1))
#model_btm <- lm(y_btm ~ poly(x, 6))  # Pas een 2e-graad polynoom toe
#model_fiets <- lm(y_fiets ~ poly(x, 7))  # Pas een 2e-graad polynoom toe

# Schat de parameters
lines(x, predict(fit_voet, newdata = list(x = x)), col = "#A58AFF", lwd = 2)
#fit_BTM = lines(x, predict(model_btm), col="#F8766D")
#fit_fiets = lines(x, predict(model_fiets), col="#C49A00")

# Toon de geschatte parameters
params_voet <- coef(fit_voet)  # Haal de geschatte parameters op: a, b, c
#params_btm <- coef(model_btm)
#params_fiets <- coef(model_fiets)

# Genereer de formule tekst
# formula_text_voet <- paste("y_voet = ", round(params_voet["a"], 2), " * exp(-(x - ", round(params_voet["b"], 2), 
#                            ")^2 / (2 * ", round(params_voet["c"], 2), "^2))", sep = "")
formula_text_voet <- paste("y_voet = exp(-(x)^2 / (2 * ", round(params_voet["c"], 2), "^2))", sep = "")
# formula_text_BTM <- paste("y_btm = ", round(params_btm[1], 2), 
#                           " + ", round(params_btm[2], 2), " * x", 
#                           " + ", round(params_btm[3], 2), " * x^2", 
#                           " + ", round(params_btm[4], 2), " * x^3", 
#                           " + ", round(params_btm[5], 2), " * x^4", 
#                           " + ", round(params_btm[6], 2), " * x^5", 
#                           sep = "")
# formula_text_fiets <- paste("y_fiets = ", round(params_fiets[1], 2), 
#                             " + ", round(params_fiets[2], 2), " * x", 
#                             " + ", round(params_fiets[3], 2), " * x^2", 
#                             " + ", round(params_fiets[4], 2), " * x^3", 
#                             " + ", round(params_fiets[5], 2), " * x^4", 
#                             " + ", round(params_fiets[6], 2), " * x^5", 
#                             " + ", round(params_fiets[7], 2), " * x^6", 
#                             sep = "")
# Voeg de formule als tekst toe aan de grafiek
text(x = 1, y = 0.93, labels = formula_text_voet, col = "#A58AFF", cex = 1, pos = 4)
#text(x = 2.2, y = 0.45, labels = formula_text_BTM, col = "#F8766D", cex = 1, pos = 4)
#text(x = 2.2, y = 0.28, labels = formula_text_fiets, col = "#C49A00", cex = 1, pos = 4)

dev.off()  # Sluit het grafisch apparaat en sla het bestand op
