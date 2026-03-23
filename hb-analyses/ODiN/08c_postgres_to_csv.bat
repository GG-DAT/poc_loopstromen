REM psql -U postgres -d loopstromen -c "\COPY pc4_odin_subset_1_instelling TO 'C:/Users/Rs1/Goudappel Groep/prj-g-Loopstromenmodel - materiaal loopstromenmodel/code_pok/ODiN_analyse/Input/pc4_odin_subset_1_onderwijsinstelling.csv' CSV HEADER"
REM psql -U postgres -d loopstromen -c "\COPY pc4_odin_subset_trein_voet_1_instelling TO 'C:/Users/Rs1/Goudappel Groep/prj-g-Loopstromenmodel - materiaal loopstromenmodel/code_pok/ODiN_analyse/Input/pc4_odin_subset_trein_voet_1_onderwijsinstelling.csv' CSV HEADER"
REM psql -U postgres -d loopstromen -c "\COPY pc4_odin_subset TO 'C:/Users/Rs1/Goudappel Groep/prj-g-Loopstromenmodel - materiaal loopstromenmodel/code_pok/ODiN_analyse/Input/pc4_odin_subset.csv' CSV HEADER"
REM psql -U postgres -d loopstromen -c "\COPY pc4_odin_subset_trein_voet TO 'C:/Users/Rs1/Goudappel Groep/prj-g-Loopstromenmodel - materiaal loopstromenmodel/code_pok/ODiN_analyse/Input/pc4_odin_subset_trein_voet.csv' CSV HEADER"
psql -U postgres -d loopstromen -c "\COPY pc4_odin_subset_incl_15_17 TO 'C:/Users/Rs1/Goudappel Groep/prj-g-Loopstromenmodel - materiaal loopstromenmodel/code_pok/ODiN_analyse/Input/pc4_odin_subset_incl_15_17.csv' CSV HEADER"

pause