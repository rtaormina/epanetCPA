classdef EpanetCPASimulation
    % Class for running a step-by-step EPANET simulation with (and without) cyber-attacks.
    
	properties
        epanetMap           % EpanetMap instance contaning the modified .inp file;
        
        attacks             % List of cyber-physical attacks (if empty, load original map)                
                
        display_every       % 0 = no display, otherwise display_ever x iterations
        
        startTime           % startTime of the simulation
        
        simTime             % current time into simulation        
        
        readings            % readings of the simulation                        
        
        symbolDict          % dictionary with all symbols needed attack begin/stop
        
        T, cT               % array of times and clocktimes
        
        attackTrack         % track attack history (on/off for each attack, in time)                
        
        alteredReadings     % here are the information regarding the altered readings at PLC and SCADA layer
        
        whatToStore         % readings and variables to store     
        
        tstep               % time step (STILL TO DO)
                
        patternStepLength   % step length of demand pattern
        
        dds         % NEW FOR OPTIMISIMUL desider demands cell array
        
    end
    
    
    % public methods
    methods
        
    function self = EpanetCPASimulation(epanetMap, attacks, cyberoptions)        
        % Constructor class for EpanetCPASimulation.
        
        % fill properties
        self.epanetMap      = epanetMap;
        self.attacks        = attacks; 
        self.display_every  = cyberoptions.verbosity;
        self.whatToStore    = cyberoptions.what_to_store;      
        
        %% NEW FOR OPTIMISIMUL
        % store desired demand to compute unmet demands    
        self.dds = {};
        
        % load map file
        EpanetHelper.epanetloadfile(self.epanetMap.modifiedFilePath);
        
        % validate attacks (TO DO: make sure all attacks have a validation method)       
        for i = 1 : numel(self.attacks)           
            if ismethod(self.attacks{i}, 'validateAttack')                
                % check for attack where validation has been enabled
                if isa(self.attacks{i},'AttackOnCommunication')
                    % if AttackOnCommunication we need to send systems
                    self.attacks{i} = self.attacks{i}.validateAttack(self.epanetMap.cyberlayer);
                end
            else
                warning('Class %s has no validateAttack method yet!', class(self.attacks{i}));
            end            
        end
        
        
        % get nNodes and nLinks (TO DO: maybe you should store this somewhere...)
        nNodes = 0; nLinks = 0;
        [~,nNodes] = calllib(...
            'epanet2','ENgetcount', EpanetHelper.EPANETCODES('EN_NODECOUNT'),nNodes);
        [~,nLinks] = calllib(...
            'epanet2','ENgetcount', EpanetHelper.EPANETCODES('EN_LINKCOUNT'),nLinks);

        % get all node and link indexes to store
        self.whatToStore.nodeIdx = [];
        self.whatToStore.linkIdx = [];
        switch self.whatToStore.sensors{1}
            case 'everything'
                % we will store readings for all nodes
                self.whatToStore.nodeIdx = 1 : nNodes;
                % ... and all links
                self.whatToStore.linkIdx = 1 : nLinks;            
                % store all variables as well
                self.whatToStore.nodeVars = {'PRESSURE','HEAD','DEMAND'};
                self.whatToStore.linkVars = {'FLOW', 'STATUS', 'SETTING','ENERGY'}; 
            case 'all'
                % we will store readings for all nodes
                self.whatToStore.nodeIdx = 1 : nNodes;
                % ... and all links
                self.whatToStore.linkIdx = 1 : nLinks; 
            case 'all nodes'
                % we will store readings for all nodes
                self.whatToStore.nodeIdx = 1 : nNodes;
            case 'all links'
                % we will store readings for all links
                self.whatToStore.linkIdx = 1 : nLinks; 
            otherwise
                for i = 1 : numel(self.whatToStore.sensors)
                    thisId = self.whatToStore.sensors{i};
                    [thisIdx, ~, isNode] = EpanetHelper.getComponentIndex(thisId);
                    if isNode
                        self.whatToStore.nodeIdx = cat(1,self.whatToStore.nodeIdx,thisIdx);
                    else
                        self.whatToStore.linkIdx = cat(1,self.whatToStore.linkIdx,thisIdx);
                    end
                end
        end
        
        % get stored nodes and links IDs
        self.whatToStore.nodeID = cell(size(self.whatToStore.nodeIdx,1),1);
        self.whatToStore.linkID = cell(size(self.whatToStore.linkIdx,1),1);
        for j = 1 : numel(self.whatToStore.nodeIdx)
            thisIdx = self.whatToStore.nodeIdx(j);
            self.whatToStore.nodeID{j} = EpanetHelper.getComponentId(thisIdx,1);
        end
        
        for j = 1 : numel(self.whatToStore.linkIdx)
            thisIdx = self.whatToStore.linkIdx(j);
            self.whatToStore.linkID{j} = EpanetHelper.getComponentId(thisIdx,0);
        end                        
        
        % initialize time
        self.simTime = 0;      

        % get starttime constant
        HOURS_TO_SECONDS = 3600;
        STARTTIME = int64(0);
        [~,STARTTIME] = calllib(...
            'epanet2','ENgettimeparam', ...
            EpanetHelper.EPANETCODES('EN_REPORTSTART'),STARTTIME);
        self.startTime = double(STARTTIME/HOURS_TO_SECONDS);

        % initialize readings arrays
        self.readings.PRESSURE = []; self.readings.DEMAND = []; 
        self.readings.FLOW     = []; self.readings.SETTING = []; 
        self.readings.ENERGY   = []; self.readings.HEAD = []; 
        self.readings.STATUS   = [];

        % initialize time, clocktime and attack track arrays
        self.T = []; self.cT = []; self.attackTrack = [];   
        
        % get pattern step length
        EN_PATTERNSTEP = EpanetHelper.EPANETCODES('EN_PATTERNSTEP');
        self.patternStepLength = double(0);
        [errorcode, self.patternStepLength] = calllib(...
            'epanet2', 'ENgettimeparam',...
            EN_PATTERNSTEP, self.patternStepLength);
        self.patternStepLength = double(self.patternStepLength);

        % initialize symbol dictionary
        self = initializeSymbolDictionary(self);

        % initialize altered readings
        self.alteredReadings = [];

        EpanetHelper.epanetclose();   
    end        
    
    function self = run(self)       
        % runs the hydraulic simulation.
        
        % open simulation
        EpanetHelper.epanetloadfile(self.epanetMap.modifiedFilePath);
                
        % set patterns
        self.epanetMap.patterns = self.epanetMap.setPatterns();
        
        % set initial tank levels        
        self.epanetMap.setInitialTankLevels();
                        
        % deactivate all map controls
        self.epanetMap.deactivateControls();
        
        % zero based demands (for pda)
        if self.epanetMap.usePDA
            self.zeroBaseDemands();
        end
             
        %% MAIN LOOP
        % open the hydraulic solver
        errorcode = calllib('epanet2', 'ENopenH');
        
        % initialize the hydraulic solver
        INITFLAG  = 0;
        errorcode = calllib('epanet2', 'ENinitH', INITFLAG);
        HOURS_TO_SECONDS = 3600;

        % simulation loop
        self.tstep = self.epanetMap.h_tstep;
        tstep  =  self.tstep;
		
        while tstep && ~errorcode 

            TIME = double(self.simTime)/HOURS_TO_SECONDS;
            if (TIME>0) && mod(TIME,self.display_every)<=0.00001% TODO: make this clearer
                echoString = sprintf('TIME: %.3f\n',TIME);
                fprintf(echoString);
            end 
            
            % update component settings (for pda)
            if self.epanetMap.usePDA
                %% NEW FOR OPTIMISIMUL
                self = self.updateComponentSettings();
            end

            % run hydraulic simulation step
            [self,tstep] = self.hydraulicStep(tstep);             
            self.tstep = tstep;            
            [~, self.simTime] = calllib('epanet2', 'ENrunH', self.simTime);
            
            % update simulation state
            self = self.getCurrentState();  

            % continue to the next time step ...
            [errorcode, tstep] = calllib('epanet2', 'ENnextH', tstep);
            self.tstep = tstep;
        end
        
        % close simulation
        EpanetHelper.epanetclose();
    end
    
    % end of public methods
    end           
    
    
    % private methods
    methods (Access = private)
            
    function [self,tstep] = hydraulicStep(self, tstep) 
        % execute hydraulic step using the epanet toolkit.
		
        %% Work with symbol dictionaries
        % update dictionary
        self = updateSymbolDictionary(self);
        
        % get all systems
        systems = self.epanetMap.cyberlayer.systems;
        for j = 1 : numel(systems)
            % get PLC name
            controllerName = systems(j).name;
            % intialize dict for this PLC
            eval(sprintf('%sdict = containers.Map();', controllerName)); 
            % sensors read            
            sensors = cat(2,systems(j).sensors,systems(j).sensorsIn);
            for k = 1 : numel(sensors)
                % remove previx (P_, F_ or S_...)
                sensor = sensors{k};
                sensor = regexp(sensor,'_','split');
                sensor = sensor{2};
                try
                    reading = self.symbolDict(sensor);
                    eval(sprintf('%sdict(sensor) = reading;',controllerName));
                catch
                    % fprintf('Sensor %s not used in control logic:
                    % skipping.',sensor)
                    % fprintf('Sensor %s non used in control logic\n', sensor);
                end
                
            end
        end
        
        % create SCADA dictionary
        SCADAdict = [self.symbolDict;containers.Map()]; % concatenation so it's deep-copy        
        
        %% Evaluate, perform and track attacks
        
        % get number of attacks
        nAttacks   = numel(self.attacks);  

        % counter for attacks in place
        attacksInPlace = 0;
        
        % Cycle through attacks
        for i = 1 : nAttacks
            % for each attack, check their conditions and see whether they
            % have to start, end or continue...
            [attack, self] = self.attacks{i}.evaluateAttack(self);
            
            % alter readings if attack is in place and alters readings,
            % i.e. AttackOnSensor & AttackOnCommunication.
            attackAltersReading = isprop(attack,'alteredReading');
            if isa(attack,'AttackOnCommunicationNew') && ~attack.targetIsSensor 
                % readings are not altered if AttackOnCommunication targets
                % incoming actuator transmission.
                attackAltersReading = false;
            end
            
            if attack.inplace && attackAltersReading
                % flag this if SCADA readings are modified by attack due to
                % cascade effect
                doesPropagate = false;
                
                % get layer and target
                layer  = attack.layer;
                % (first remove prefix from target)
                temp = regexp(attack.target,'_','split');
                target = temp{2}; 
        
                alteredReading = attack.alteredReading;
                
                % create new entry for altered readings
                self = self.storeAlteredReadingEntry(...
                    layer, target, alteredReading);                
 
                if strcmp(layer,'PHY')
                    % direct attack to sensor
                    controllerName = 'NO PLC';
                    doesPropagate = true; % sensor manipulation always alters SCADA
                else
                    % attack to connection
                    thisController = systems(ismember({systems.name},layer));                        
                    controllerName = thisController.name;
                    % modify PLC dictionary
                    eval(sprintf('%sdict(target) = alteredReading;', controllerName)); 
                    
                    % alter downstream if sensor directly connected to
                    % controller
                    if ismember(target, thisController.sensors)
                        doesPropagate = true;
                    end
                end

                % Altered signal may affect other systems down the
                % line. We need to alter these readings too.
                
                % if attack at physical layer, then alter readings of PLC
                % reading the sensor.
                if strcmp(layer,'PHY')
                    for j = 1 : size(systems,1)
                        controllerName_ = systems(j).name;
                        if (strcmp(controllerName_,controllerName) == 0) && ...                                 
                            (sum(ismember(systems(j).sensors,target)) > 0)
                            % Modify PLC dictionary and create new
                            % entry for altered readings
                            eval(sprintf('%sdict(target) = alteredReading;', controllerName_));                                  
                            self = self.storeAlteredReadingEntry(...
                                controllerName_, target, alteredReading);                                
                        end
                    end
                end
                
                % check for further propagation, including SCADA
                if doesPropagate
                    for j = 1 : size(systems,1)
                        controllerName_ = systems(j).name;
                        if (strcmp(controllerName_,controllerName) == 0) && ...
                                (sum(ismember(systems(j).sensorsIn,target))>0)                                
                            % Modify PLC dictionary and create new
                            % entry for altered readings
                            eval(sprintf('%sdict(target) = alteredReading;', controllerName_));                                  
                            self = self.storeAlteredReadingEntry(...
                                controllerName_, target, alteredReading);                                
                        end
                    end  
                end
            end

            % store attacks
            self.attacks{i} = attack;
            
            % update count of attacks in place
            attacksInPlace = attacksInPlace + attack.inplace;                                        
        end
                         
        
        %% Override control logic
        for i = 1 : numel(systems)
            thisController = systems(i);
            try
                eval(sprintf('PLCdict = %sdict;',thisController.name));
            catch
                disp('error')
            end
            % this doesn't look as nice as if it were a method within the
            % EpanetMap class, or PLC better
            % MAXLEVELS and CLOCKTIME, TIME should be sent along too
            % add generic variables such as TIME or MAXLEVELs from SCADAdict
            if ~strcmp(thisController.name,'SCADA')
                % add generic variables such as TIME or MAXLEVELs from SCADAdict
                scada_keys = SCADAdict.keys;
                for i = 1 : numel(scada_keys)
                    thisKey = scada_keys{i};
                    isMaxLevel = strfind(thisKey,'MAXLEVEL')==1;
                    if isempty(isMaxLevel) 
                        isMaxLevel = 0;
                    end
                    if ismember(thisKey,['TIME','CLOCKTIME']) | isMaxLevel
                        PLCdict(thisKey) = SCADAdict(thisKey);
                    end
                end
            end
            self.overrideControls(thisController, PLCdict);
        end
        
        % activate dummy controls if needed
        self = self.activateDummyControls(tstep);
                
        %% Track attack history
        attackFlag = zeros(1,nAttacks);
        for i = 1 : nAttacks
            attackFlag(i) = self.attacks{i}.inplace;      
        end
        self.attackTrack = cat(1,self.attackTrack,attackFlag);

        end
    
    function self = getCurrentState(self)
        % store time, nodes/links readings
        
        % TO DO: rename the method? Put HOURS_TO_SECONDS somewhere else?

        % store time vars
        HOURS_TO_SECONDS = 3600;
        TIME = double(self.simTime)/HOURS_TO_SECONDS;
        % time
        self.T = cat(1,self.T,TIME);
        % ... and clocktime
        self.cT = cat(1,self.cT,mod(self.startTime+TIME,24));
        
        % store nodal readings (if there are nodes)
        if ~isempty(self.whatToStore.nodeIdx)
            variables = self.whatToStore.nodeVars;
            nNodes = numel(self.whatToStore.nodeIdx);            
            index = self.whatToStore.nodeIdx;
            for j = 1 : numel(variables)
                this_var = variables{j};
                value = repmat(0.0,1,nNodes);
                for n = 1:nNodes    
                    try
                        [errorcode, value(n)] = calllib('epanet2', 'ENgetnodevalue', index(n),...
                            EpanetHelper.EPANETCODES(['EN_',variables{j}]), value(n));
                    catch EPANET_VARIABLE_EXCEPTION
                        if isempty(this_var)
                            error('No node variables specified in CPA file.')
                        else
                            error('Variable %s does not exist for epanet nodes.', this_var)
                        end
                    end
                end
                self.readings.(this_var) = cat(1,self.readings.(this_var),double(value));
            end
        end
            
        % store link readings (if there are links)
        if ~isempty(self.whatToStore.linkIdx)
            variables = self.whatToStore.linkVars;
            nLinks = numel(self.whatToStore.linkIdx);
            index = self.whatToStore.linkIdx;
            for j = 1 : numel(variables)
                this_var = variables{j};
                value = repmat(0.0,1,nLinks);
                for n = 1:nLinks
                    try
                        [errorcode, value(n)] = calllib('epanet2', 'ENgetlinkvalue', index(n),...
                            EpanetHelper.EPANETCODES(['EN_',variables{j}]), value(n));
                    catch EPANET_VARIABLE_EXCEPTION
                        if isempty(this_var)
                            error('No link variables specified in CPA file.')
                        else
                            error('Variable %s does not exist for epanet link.', this_var)
                        end
                    end
                end                
                self.readings.(this_var) = cat(1,self.readings.(this_var),double(value));
            end
        end
    end            
    
    function self = initializeSymbolDictionary(self)
        % initialize symbol dictionary
        
        % TO DO: merge it with in some initializeSimulation of sorts??

        % initialize
        self.symbolDict = containers.Map();
        
        % add TANKS max levels (these won't change during simulation)
        EN_MAXLEVEL = EpanetHelper.EPANETCODES('EN_MAXLEVEL');
        TANKS = self.epanetMap.components('TANKS'); 
        for i = 1 : numel(TANKS)
            thisTankIndex = EpanetHelper.getComponentIndex(TANKS{i});
            maxTankLevel  = EpanetHelper.getComponentValue(thisTankIndex, true, EN_MAXLEVEL);
            maxTankLevel  = maxTankLevel - 10^-3; % ... minus a bit or it won't work
            % create parsing CONSTANT
            eval(sprintf('self.symbolDict(''%s%s'') = %d;',...
                'MAXLEVEL',TANKS{i},maxTankLevel));   
        end
        clear TANKS
    end
    
    function self = updateSymbolDictionary(self)                      
        % update the symbol dictionary used for controls and attacks.
        HOURS_TO_SECONDS = 3600;
        nAttacks = numel(self.attacks);
                
        % get time into the simulation and clocktime and insert into dictionary
        TIME = double(self.simTime)/HOURS_TO_SECONDS;
        self.symbolDict('TIME') = TIME;
        self.symbolDict('CLOCKTIME') = mod(self.startTime+TIME,24);                

        % put attack status symbols in dictionary
        %(i.e. ATT1 = 1, then 1st attack is currently ON)
        for i = 1 : nAttacks
            eval(sprintf('self.symbolDict(''%s%d'') = %d;',...
                'ATT', i,self.attacks{i}.inplace));   
        end
        
        % put component symbols in dictionary for each control
        % TO DO: need to avoid multiple check of the same sensors!
        for i = 1 : numel(self.epanetMap.controls)
            % get the control sensor ID
            thisSensor = EpanetHelper.getComponentId(self.epanetMap.controls(i).nIndex, 1);       
            % if it's a time-based control nIndex == 0. if prevents error
            if self.epanetMap.controls(i).nIndex > 0
                eval(sprintf('self.symbolDict(''%s'') = EpanetHelper.getComponentValueForAttacks(''%s'');',...
                    thisSensor,thisSensor));
            end
        end
        
        
        % put component symbols in dictionary for each attack for both
        % initial...
        for i = 1 : nAttacks
            % initial condition
            thisCondition = self.attacks{i}.ini_condition;
            % retrieve vars
            vars = symvar(thisCondition);
            for j = 1 : numel(vars)
                thisVar = vars{j};
                % check if symbol has already been included (search dict
                % keys) MAXLEVELS are never updated, TIME, CLOCKTIME and
                % ATTx are evaluated beforehad.
                if ~strcmp(thisVar,'TIME') && ~strcmp(thisVar,'CLOCKTIME') &&...
                        ~strncmp(thisVar,'ATT',3) && ~strncmp(thisVar,'MAXLEVEL',8)
                    eval(sprintf('self.symbolDict(''%s'') = EpanetHelper.getComponentValueForAttacks(''%s'');',...
                        thisVar,thisVar));
                end
            end
        end
        
        % ... and ending conditions
        for i = 1 : nAttacks
            % initial condition
            thisCondition = self.attacks{i}.end_condition;
            % retrieve vars
            vars = symvar(thisCondition);
            for j = 1 : numel(vars)
                thisVar = vars{j};
                % check if symbol has already been included (search dict
                % keys) MAXLEVELS are never update, TIME, CLOCKTIME and
                % ATTx are evaluated beforehad.
                if ~strcmp(thisVar,'TIME') && ~strcmp(thisVar,'CLOCKTIME') &&...
                        ~strncmp(thisVar,'ATT',3) && ~strncmp(thisVar,'MAXLEVEL',8)
                    eval(sprintf('self.symbolDict(''%s'') = EpanetHelper.getComponentValueForAttacks(''%s'');',...
                        thisVar,thisVar));
                end
            end
        end
        
        % Add attack targets (needed for junctions and attacks to
        % communications)
        for i = 1 : nAttacks
            % target
            if ~strcmp(self.attacks{i}.layer,'CTRL')
                thisVar = self.attacks{i}.target;
                eval(sprintf('self.symbolDict(''%s'') = EpanetHelper.getComponentValueForAttacks(''%s'');',...
                    thisVar,thisVar));
            end
        end 
        
    end   
       
    function [] = overrideControls(self,thisController,PLCdict)
        % override control logic by calling control objects in 
        % the epanetMap
        
        % retrieve controls and call overide method
        controls = self.epanetMap.controls;
        for i = 1 : numel(thisController.controlsID)
            ix = thisController.controlsID(i);
            controls(ix).overrideControl(PLCdict);
        end       
    end
    
    function self = activateDummyControls(self, tstep)
        % complete override by activating dummy controls
        % TO DO: merge with overrideControls?

        % retrieve active dummy controls
        if sum([self.epanetMap.dummyControls.isActive]) > 0            
            for i = 1 : numel(self.attacks)
                if self.attacks{i}.inplace == 1
                    ix = self.attacks{i}.actControl;
                    if ~isempty(ix)
                        lS = self.attacks{i}.setting;
                        time = int64(self.simTime + tstep);
                        self.epanetMap.dummyControls(ix) = ...
                            self.epanetMap.dummyControls(ix).activateWithValues(lS,time);
                    end
                end
            end
        end
    end
    
    function self = storeAlteredReadingEntry(self, layer, target, alteredReading)  

        % creates and store new entry for altered readings
        thisEntry.time     = self.T(end);
        thisEntry.layer    = layer;
        thisEntry.sensorId = target;
        thisEntry.reading  = alteredReading;    
        
        % check if target is node or link to see if reading is pressure or flow              
       
        [~, ~, isNode] = EpanetHelper.getComponentIndex(target);
        if isNode
            thisEntry.variable = 'PRESSURE';
        else
            thisEntry.variable = 'FLOW';
        end
        self.alteredReadings = cat(1,self.alteredReadings,thisEntry);
    end
    
    function self = zeroBaseDemands(self)
        % TO DO: this can be moved to EpanetHelper.addDummyComponents() 
        % cycle through all nodes with base demand > 0 and zero them
        EN_BASEDEMAND = 1;
        junctions = keys(self.epanetMap.pdaDict);
        for i = 1:length(junctions)
            ix_dummy = EpanetHelper.getComponentIndex(junctions{i});
            EpanetHelper.setComponentValue(ix_dummy,0.0,EN_BASEDEMAND);
        end
    end 
    
    function self = updateComponentSettings(self)

        % loop through demand nodes	
        pdaDict = self.epanetMap.pdaDict;
        junctions = keys(pdaDict);

        % get pattern length
        patterns = self.epanetMap.patterns;
        [P_length,~] = size(patterns);
        
        %% NEW FOR OPTIMISIMUL
        % store desired demand to compute unmet demands       
        dd = containers.Map();
        for i = 1:length(junctions)
            thisJunction = junctions{i};

            % get current pattern timestep
            timeNow = double(self.simTime);
            patternStep = rem((floor(timeNow/self.patternStepLength)+1),P_length); 
            if patternStep == 0
                patternStep = P_length;
            end
            % get pattern multiplier value for junction
            ixPattern = pdaDict(thisJunction).ixPattern;
            PM_value = patterns(patternStep,ixPattern);

            % calculate actual demand
            BD_value = pdaDict(thisJunction).baseDemand;
            FCV_setting = BD_value*PM_value;

            % set FCV setting to actual demand
            valve_ix = pdaDict(thisJunction).ixFCV;
            EpanetHelper.setComponentValue(...
                    valve_ix,FCV_setting,EpanetHelper.EPANETCODES('EN_SETTING'));

            % set emitter coefficient
            emitter_ix = pdaDict(thisJunction).ixEmit;
            emitter_coef = self.calcEmitterCoef(FCV_setting,emitter_ix);
%             if length(P_des) == 1
%                  
%             else
%                 error('Different values of Pdes not supported yet');
%                 % emitter_coef = calcEmitterCoef(self,...
%                 % self.epanetMap.HFR,P_min,P_des(i),...
%                 % self.epanetMap.emitterExponent,FCV_setting,emitter_ix); 
%             end

            %set emitter coefficient value
            EpanetHelper.setComponentValue(...
                emitter_ix,emitter_coef,EpanetHelper.EPANETCODES('EN_EMITTER'));	
            
            %% NEW FOR OPTIMISIMUL
            % store desired demand to compute unmet demands
            dd(thisJunction) = FCV_setting;            
        end
        
        %% NEW FOR OPTIMISIMUL
        % concatenate des_demands
        self.dds = cat(1,self.dds,{dd});
        
    end	
    
    function eCoef = calcEmitterCoef(self,demand,emitter_ix) 
        % calculates emitter coefficient using the specified head-flow-relationship 
        % equation specified by the user (currently stored in the map)
        
        % get pda options
        emitterExp = self.epanetMap.pdaOptions.emitterExponent; % emitter exp
        P_min = self.epanetMap.pdaOptions.Pmin; % minimum pressure 
        P_des = self.epanetMap.pdaOptions.Pdes; % desired pressure(s)
        HFR = self.epanetMap.pdaOptions.HFR; % head flow relationship
        
        % TO DO: substitute with switch statement
        if strcmp(HFR,'Wagner')
            eCoef = demand/((P_des-P_min)^emitterExp);
        elseif strcmp(HFR,'Salgado-Castro')
            if emitterExp == 1.0
                eCoef = demand/((P_des-P_min)^emitterExp);
            else
                error('When using Salgado-Castro HFR, emitter exponent must be 1.0')
            end 
        elseif strcmp(HFR,'Bhave')
            eCoef = 1e9; %this is an arbitrarily large value
        elseif strcmp(HFR,'Fujiwara')
            %This HFR can't be simplified to match the emitter equation
            %without reading the pressure value (one timestep prior)
            if emitterExp==2.0
                EN_PRESSURE = 11;
                EN_ELEVATION = 0;
                thisPres = EpanetHelper.getComponentValue(...
                        emitter_ix,1,EN_PRESSURE);
                thisElev = EpanetHelper.getComponentValue(...
                        emitter_ix,1,EN_ELEVATION);
                H_des = P_des+thisElev;
                H_min = P_min+thisElev;
                H = thisPres+thisElev;
                if H < H_des
                    eCoef = demand*((3*P_des-2*thisPres-P_min)/((P_des-P_min)^3)*...
                        (1+(P_min^2-2*thisPres*P_min)/(thisPres^2)));
                else
                    eCoef = demand/(P_des^2);
                end
            else
                error('When using Fujiwara HFR, emitter exponent must be 2.0')
            end
        else
            error('No valid head-flow relationship specified. Using default. Options: Wagner, Salgado-Castro, Bhave, Fujiwara')
        end
    end
    % end of private methods
    end            
end
    