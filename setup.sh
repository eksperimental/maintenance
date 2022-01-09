#!/bin/sh

git config --global pull.ff only
git config --global user.name "Maintenance App"
git config --global user.email meaintenance-beam@autistici.org
git config --global advice.addIgnoredFile false
git config --global fetch.fsckobjects true
git config --global transfer.fsckobjects true
git config --global receive.fsckobjects true
