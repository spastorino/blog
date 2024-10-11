# santiagopastorino.com site

This repo contains my personal website, blog and resources like talks
and workshops.

## Update procedure

```
for i in static/why-rust static/intro-to-rust static/contributing-to-rustc; do pushd $i; git pull; popd; done
hugo -d public --minify --theme beautifulhugo
pushd public
git add .
git commit -am "Deploy website"
git push
popd
git add static public
git commit -m "Update static"
git push
```
