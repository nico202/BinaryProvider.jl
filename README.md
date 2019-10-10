# BinaryProvider

## Basic concepts

This is a Mock package. The aim is to prevent BinaryProvider from
trying to provide binaries. We want a free and reproducible
environment, so we install binaries only from source via [GNU guix](http://guix.gnu.org/).

## Usage

This package is intended as a replace for BinaryProvider that just
prints debugging information to help in packages Julia Packages under guix.

When packaging a julia package under guix, just add this package in
stead of the real BinaryProvider.
