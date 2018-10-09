%% Examples of cyber-physical attacks on WADI testbed

%% INITIALIZATION
clear; clc;

% add path for epanetCPA toolbox
addpath('.\epanetCPA\')

% add location of the map and cpa files  
inpFilePath = 'minitown_map.inp';

% Define scenario
scenarioFolder = './scenarios/minitown/';
cpaFilePath = 'minitown_attack.cpa';
noAttackCpaFile = 'minitown_no_attacks.cpa'
exp_name = cpaFilePath(1:strfind(cpaFilePath,'.cpa')-1);


% Similation without attacks (used for comparison).
% It is slower we specified to store all EPANET variables.
simul = EpanetCPA(inpFilePath, [scenarioFolder, noAttackCpaFile]); % 
simul = simul.run();
simul.outputResults('no_attacks');

% Similation with attacks
simul = EpanetCPA(inpFilePath, [scenarioFolder,cpaFilePath]); % 
simul = simul.run();
simul.outputResults(exp_name);