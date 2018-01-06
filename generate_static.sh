#!/bin/sh

buster generate
find static/ -type f \( -name '*.html' -o -name '*.txt' -o -name '*.rss' \) -exec sed -i 's,http://localhost:2368,https://santiagopastorino.com,g' {} +
find static/ -type f \( -name '*.html' -o -name '*.txt' -o -name '*.rss' \) -exec sed -i 's,http://fonts.googleapis.com,https://fonts.googleapis.com,g' {} +
find static/ -type f \( -name '*.html' -o -name '*.txt' -o -name '*.rss' \) -exec sed -i 's,http://www.gravatar.com,https://www.gravatar.com,g' {} +
find static/ -type f \( -name '*.html' -o -name '*.txt' -o -name '*.rss' \) -exec sed -i 's,http://code.jquery.com,https://code.jquery.com,g' {} +
find static/ -type f \( -name '*.html' -o -name '*.txt' -o -name '*.rss' \) -exec sed -i 's,http://cloud.feedly.com,https://cloud.feedly.com,g' {} +
find static/ -type f \( -name '*.html' -o -name '*.txt' -o -name '*.rss' \) -exec sed -i 's,rss/index.html,rss/index.rss,g' {} +
