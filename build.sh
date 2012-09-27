#!/bin/bash 

which bundle > /dev/null
if [ "$?" -ne "0" ]; then
  echo "bundler is missing. Please install bundler (http://gembundler.com/)."
  exit 1
fi

echo "Installing dependencies..."
echo "If problems occur, consider updating RubyGems with the command 'sudo gem update --system'"

bundle install
