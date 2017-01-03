#!/bin/sh

buster generate
find static/ -type f -name '*.html' -o -name '*.txt' -o -name '*.rss' | xargs sed -i '' -e 's,http://localhost:2368,https://santiagopastorino.com,g'
find static/ -type f -name '*.html' -o -name '*.txt' -o -name '*.rss' | xargs sed -i '' -e 's,http://fonts.googleapis.com,https://fonts.googleapis.com,g'
find static/ -type f -name '*.html' -o -name '*.txt' -o -name '*.rss' | xargs sed -i '' -e 's,http://www.gravatar.com,https://www.gravatar.com,g'
find static/ -type f -name '*.html' -o -name '*.txt' -o -name '*.rss' | xargs sed -i '' -e 's,http://code.jquery.com,https://code.jquery.com,g'
