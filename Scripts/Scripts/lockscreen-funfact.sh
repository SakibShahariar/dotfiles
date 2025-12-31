curl -s https://uselessfacts.jsph.pl/api/v2/facts/random?language=en | grep -oP '"text":"\K[^"]+'
