#!/bin/sh

echo "Downloading io.js..."
curl -s -o iojs.tar.gz https://iojs.org/dist/v1.1.0/iojs-v1.1.0-darwin-x64.tar.gz
tar -zxf iojs.tar.gz
export PATH=$PWD/iojs/bin:$PATH
node -v

echo "Downloading latest Atom release..."
curl -s -L "https://atom.io/download/mac" \
-H 'Accept: application/octet-stream' \
-o atom.zip

mkdir atom
unzip -q atom.zip -d atom

echo "Using Atom version:"
ATOM_PATH=./atom ./atom/Atom.app/Contents/Resources/app/atom.sh -v

echo "Installing required packages..."
atom/Atom.app/Contents/Resources/app/apm/node_modules/.bin/apm install autocomplete-plus

echo "Downloading package dependencies..."
atom/Atom.app/Contents/Resources/app/apm/node_modules/.bin/apm clean
atom/Atom.app/Contents/Resources/app/apm/node_modules/.bin/apm install

if [ -f ./node_modules/.bin/coffeelint ]; then
  echo "Linting package..."
  ./node_modules/.bin/coffeelint lib spec
fi

echo "Running specs..."
ATOM_PATH=./atom atom/Atom.app/Contents/Resources/app/apm/node_modules/.bin/apm test --path atom/Atom.app/Contents/Resources/app/atom.sh

exit
