

pause 

REM psql -U postgres -d loopstromen -c "\copy odin_aantallen (onderwijslocatie, aantal_verplaatsingen, aantal_respondenten, aantal_verplaatsingen_trein, aantal_trein_voet, gemiddelde_loopafstand, maximale_loopafstand, minimale_loopafstand, onderwijsstation, aandeel_voet) FROM 'C:/Users/Rs1/Documents/aantallen_per_onderwijslocatie.csv' WITH CSV HEADER DELIMITER ',';"
REM psql -U postgres -d loopstromen -c "\copy odin_aantallen_trein_voet (onderwijslocatie, aantal_verplaatsingen, aantal_respondenten, aantal_verplaatsingen_trein, aantal_trein_voet, gemiddelde_loopafstand, maximale_loopafstand, minimale_loopafstand, onderwijsstation, aandeel_voet) FROM 'C:/Users/Rs1/Documents/aantallen_per_onderwijslocatie_trein_voet.csv' WITH CSV HEADER DELIMITER ',';"
REM psql -U postgres -d loopstromen -c "\copy odin_aantallen_trein_voet_incl_15_17 (onderwijslocatie, aantal_verplaatsingen, aantal_respondenten, aantal_verplaatsingen_trein, aantal_trein_voet, gemiddelde_loopafstand, maximale_loopafstand, minimale_loopafstand, onderwijsstation, aandeel_voet) FROM 'C:/Users/Rs1/Documents/aantallen_per_onderwijslocatie_trein_voet_incl_15_17.csv' WITH CSV HEADER DELIMITER ',';"
psql -U postgres -d loopstromen -c "\copy odin_aantallen_incl_15_17 (onderwijslocatie, aantal_verplaatsingen, aantal_respondenten, aantal_verplaatsingen_trein, aantal_trein_voet, gemiddelde_loopafstand, maximale_loopafstand, minimale_loopafstand, onderwijsstation, aandeel_voet) FROM 'C:/Users/Rs1/Documents/aantallen_per_onderwijslocatie_incl_15_17.csv' WITH CSV HEADER DELIMITER ',';"

pause