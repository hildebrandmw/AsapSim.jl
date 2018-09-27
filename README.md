# AsapSim

[![Build Status](https://travis-ci.org/hildebrandmw/AsapSim.jl.svg?branch=master)](https://travis-ci.org/hildebrandmw/AsapSim.jl)
[![codecov.io](https://codecov.io/gh/hildebrandmw/AsapSim.jl/graphs/badge.svg?branch=master)](https://codecov.io/gh/hildebrandmw/AsapSim.jl)
[![Project Status: Abandoned – Initial development has started, but there has not yet been a stable, usable release; the project has been abandoned and the author(s) do not intend on continuing development.](https://www.repostatus.org/badges/latest/abandoned.svg)](https://www.repostatus.org/#abandoned)

Discrete event based simulator for [Asap 4](http://vcl.ece.ucdavis.edu/asap/), an
experimental GALS manycore array. This project includes a metaprogramming based Asap 4
assembler, various core debugging tools, and support for simulating an arbitrary number of
cores all operating on their own clock domains thanks to
[LightDES](https://github.com/hildebrandmw/LightDES.jl).

This project mainly served as a tool to help me learn the architectural details of the 
Asap 4 processors and as an excuse to play around with fun metaprogramming shenanigans. It
does not replace the C++ simulator used internally within the VCL and hence has been 
abandoned in favor of working on more relevant projects.

Still, there's some fun code written here, so I'm keeping it alive for the time being.
