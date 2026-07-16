#!/bin/zsh
setopt aliases

figlet zip the function
cd lambda-package
zip -r ../function.zip .
cd ..
figlet done
