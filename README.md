## A MATLAB® toolbox for assessing the impacts of cyber-physical attacks on water distribution systems

*epanetCPA* is an open-source object-oriented MATLAB® toolbox for modelling the hydraulic response of water distribution systems to cyber-physical attacks. epanetCPA allows users to quickly design various attack scenarios and assess their impact via simulation with EPANET, a popular public-domain model for water network analysis.

If you happen to use this code for a publication, please cite the following paper which features a very early version of epanetCPA:
```
Taormina, R., Galelli, S., Tippenhauer, N. O., Salomons, E., & Ostfeld, A. (2017). Characterizing cyber-physical attacks on water distribution systems. Journal of Water Resources Planning and Management, 143(5), 04017009.
```

### Requirements:
1. **EPANET2.0**&nbsp;&nbsp;&nbsp;&nbsp;If you are runinng on a 32bit OS please download the EPANET2 Programmer's Toolkit from the [EPA website](https://www.epa.gov/water-research/epanet), and substitute the epanet2.h, epanet2.lib and epanet2.dll files in your local epanetCPA folder. Compiled librarires for a 64bit machine are included in the repository. These libraries can also be found [here](http://epanet.de/developer/64bit.html.en).

2. **MATLAB**&nbsp;&nbsp;&nbsp;&nbsp;The toolbox has been tested on MATLAB® R2014b, and it should work for later versions. Make sure that C++ compilers (e.g. Windows SDK 7.1 for MATLAB® R2014b) are installed and interfaced with MATLAB® so that dlls can be invoked.
Feedback on using epanetCPA with other versions of MATLAB is greatly appreciated. Please contact riccardo.taormina@gmail.com to provide your feedback.

3. **PYTHON**&nbsp;&nbsp;&nbsp;&nbsp;You need PYTHON installed only if you want to employ the provided IPython (Jupyter) notebook provided here for visualizing the results. If that is the case, please install the PYTHON modules required, reported at the beginning of the notebook.

### Usage
1. Edit the *main.m* file in the repository to specify which attack scenario you want to simulate. Five different scenarios are provided in the *.cpa* files contained in the repository (see following section).
2. Simulate the attack scenario by runinng *main.m*. The results are provided as one or two *csv* files depending on the type of attacks.
3. Use the IPython notebook for visualizing the results, unless you want to do otherwise.

### Examples
(Please refer to the EPANET maps in the *.inp* file for details on the water networks layout and control logic)

Folder scenarios/ctown/:
1. *scenario01.cpa*&nbsp;&nbsp;&nbsp;&nbsp; Manipulation of sensor readings arriving to PLC3. The attacker shows that tank T2 is full. The PLC closes valve V2, thus preventing the flow to reach the tank and disconnecting part of the network.
2. *scenario02.cpa*&nbsp;&nbsp;&nbsp;&nbsp; Same as *scenario01* but run using the pressure driven engine to obtain more reliable results. 
3. *scenario03.cpa*&nbsp;&nbsp;&nbsp;&nbsp; The attacker modifies the control logic of PLC5 so that some of the controlled pumps (PU10, PU11) switch on/off intermittently.
4. *scenario04.cpa*&nbsp;&nbsp;&nbsp;&nbsp;  Denial-of-service of the connection link between PLC2 and PLC1. PLC1 fails to receive updated readings of T1 water level and keeps the pumps (PU1,PU2) ON. This causes a surge in the tank T1.
5. *scenario05.cpa*&nbsp;&nbsp;&nbsp;&nbsp;   Same as *scenario04* but this time the attacker conceals the tanks surge from SCADA by altering the data sent by PLC2 to SCADA.

Folder scenarios/minitown/:
1. *minitown_attack.cpa*&nbsp;&nbsp;&nbsp;&nbsp; Denial-of-service of the connection link between PLC1 and PLC2. PLC1 fails to receive updated readings of TANK water level and keeps the pumps (PUMP1,PUMP2) ON. This causes a surge in the tank TANK. The attacker conceals the tanks surge from SCADA by altering the data sent by PLC1 to SCADA.

### Authors
Riccardo Taormina is the main developer of epanetCPA. The core of the pressure driven engine was developed by Hunter C. Douglas.

### License
epanetCPA is under the MIT license. Please read it carefully before employing the toolbox.
