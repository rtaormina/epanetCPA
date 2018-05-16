### A MATLAB® toolbox for assessing the impacts of cyber-physical attacks on water distribution systems

*epanetCPA* is an open-source object-oriented MATLAB® toolbox for modelling the hydraulic response of water distribution systems to cyber-physical attacks. epanetCPA allows users to quickly design various attack scenarios and assess their impact via simulation with EPANET, a popular public-domain model for water network analysis.

This repository is a *preview* made available for peer reviewing purposes (the toolbox has been described in a submitted publication currently under review). If you happen to use this code for a publication, please cite the following paper which features a very early version of epanetCPA:
``'
Taormina, R., Galelli, S., Tippenhauer, N. O., Salomons, E., & Ostfeld, A. (2017). Characterizing cyber-physical attacks on water distribution systems. Journal of Water Resources Planning and Management, 143(5), 04017009.
```

#### Requirements:
1. **EPANET2.0**&nbsp;In order to use the toolbox, please download and compile the EPANET2 Programmer's Toolkit from the [EPA website](https://www.epa.gov/water-research/epanet), and put the epanet2.h, epanet2.lib and epanet2.dll files in your local epanetCPA folder. If you are working on a 64bit machine, compiled DLLs can be found [here](http://epanet.de/developer/64bit.html.en)

2. **MATLAB** The toolbox has been tested on MATLAB® R2014b, and it should work for later versions. Feedback on using epanetCPA with other versions of MATLAB is greatly appreciated. Please contact riccardo.taormina@gmail.com to provide your feedback.
