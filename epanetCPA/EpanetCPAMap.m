classdef EpanetCPAMap
    % Class that implements an EPANET map (.inp file) and extends it to feature a cyber layer.
   
    properties
        originalFilePath    % original file path of .inp file
        
        modifiedFilePath    % modified file path of .inp file
        
        components          % dictionary containing map components
        
        controls            % list of control objects
        
        dummyControls       % list of control objects (dummies)
        
        cyberlayer          % cyberlayer (sensors, actuators, PLCs and SCADA)
        
        duration            % duration of simulation
        
        baseDemand          % base demand of all nodal junctions
        
        patterns            % demand patterns
        
        tankIniLevels       % tankInitiaLevels
        
        h_tstep             % hydraulic time step
        
        usePDA              % flag for pressure driven analysis
        
        pdaDict             % dictionary containing infos on artificial strings for PDA
        
        pdaOptions          % options for PDA (emitter exponent, pressures, HFR)

    end
        
    
    % public methods
    methods
        
    function self = EpanetCPAMap(mapFile, cybernodes, cyberlinks, cyberoptions, PDA_ENABLED)

        % original map file
        self.originalFilePath = mapFile; 
        
        % store properties  
        self.patterns = cyberoptions.patterns;
        self.tankIniLevels = cyberoptions.initial_conditions;
        self.pdaOptions = cyberoptions.pda_options;
        self.usePDA = PDA_ENABLED;
        
        % original map file
        self.originalFilePath = mapFile; 
                        
        % initialize map and modify .inp file
        self = self.initializeMap();
        
        % open modified file
        EpanetHelper.epanetloadfile(self.modifiedFilePath);  
        
        % get hydraulic time step
        self = getHydraulicTimeStep(self);
                                 
        % get all components
        self = getAllComponents(self);
        
        % get all controls
        self = self.getControls();
          
        % create cyber layer
        self = self.createCyberLayer(cybernodes, cyberlinks);       
                
        % close modified .inp file
        EpanetHelper.epanetclose();        
    end   
       
    function self = getControls(self)
        
        % get number of controls
        nControls = int32(0);
        [~,nControls] = ...
            calllib('epanet2','ENgetcount',...
            EpanetHelper.EPANETCODES('EN_CONTROLCOUNT'),nControls);
        
        % get total number of actionable components
        % (here normal PIPES are not considered actionable)
        nComponents =...
            numel(EpanetHelper.getComponents('PUMPS'))  + ...
            numel(EpanetHelper.getComponents('VALVES')) + ...
            numel(EpanetHelper.getComponents('OF_PIPES'));
        
        % retrieve controls
        self.controls = [];
        for i = 1 : nControls - nComponents
            self.controls = cat(1,self.controls,EpanetControl(i));
        end

        % retrieve dummy controls
        self.dummyControls = [];
        for i = numel(self.controls)+1 : nControls
            self.dummyControls = cat(1,self.dummyControls,EpanetControl(i));
        end
    end 
    
    function self = deactivateControls(self)        
        % cycle through controls and deactivate them
        for i = 1 : numel(self.controls)
            self.controls(i).deactivate();
        end
    end
    
    function patterns = setPatterns(self)        
        % get number of patterns
        n_patterns = int32(0);		
        [~, n_patterns] = calllib('epanet2', 'ENgetcount',...
            EpanetHelper.EPANETCODES('EN_PATCOUNT'), n_patterns);       
        
        if isempty(self.patterns)
            % store patterns anyway for PDA (and consistency)
            patterns = [];
            for i = 1 : n_patterns
                pattern = EpanetHelper.getPattern(i);
                patterns = cat(2,patterns,pattern');
            end   
        else
            for i = 1 : n_patterns
                errorcode = EpanetHelper.setPattern(i, self.patterns(:,i));
            end
            self.setDuration()
            patterns = self.patterns;
        end
    end
    
    function [] = setInitialTankLevels(self)        
        % exit if initial conditions have not been specified in
        % cyberoptions section of .cpa file
        if isempty(self.tankIniLevels)
            return
        end
        % cycle through all tanks and set initial level        
        TANKS = sort(self.components('TANKS'));
        EN_TANKLEVEL = EpanetHelper.EPANETCODES('EN_TANKLEVEL');
        for i = 1 : numel(TANKS)
            tankIndex = EpanetHelper.getComponentIndex(TANKS{i});
            errorcode = EpanetHelper.setComponentValue(...
                tankIndex,self.tankIniLevels(i),EN_TANKLEVEL);
        end
    end    
    
    end
    
    
    % private methods
    methods (Access = private)
          
    function self = initializeMap(self)
                
        % open original file
        EpanetHelper.epanetloadfile(self.originalFilePath); 
        
        % set modified file path
        [~,ix] = regexp(self.originalFilePath,'\.inp','match');
        self.modifiedFilePath = [self.originalFilePath(1:ix),'inpx'];
        
        % get sections
        sections = EpanetHelper.divideInpInSections(self.originalFilePath);
        
        % if PDA, add dummy components
        if self.usePDA
            P_min = self.pdaOptions.Pmin;
            junctions = EpanetHelper.getComponents('JUNCTIONS');
            [sections,self.pdaDict] = EpanetHelper.addDummyComponents(junctions, sections, P_min);
        end
                        
        % add dummy tanks, lines and controls for the tanks which can 
        % overflow (here all are supposed to possibily overflow). 
        % TODO: modify this when if you plat to add new sections 
        % to original .inp file.
        
        % get tanks that can overflow (all as for now)
        tanks = EpanetHelper.getComponents('TANKS');        
        sections = EpanetHelper.addDummyTanks(tanks, sections);

        % create temp file
        EpanetHelper.createInpFileFromSections(sections,self.modifiedFilePath)

        % close original file
        EpanetHelper.epanetclose();

        % open temp file for inizialization and to in include additional controls
        EpanetHelper.epanetloadfile(self.modifiedFilePath);    
        
        % retrieve pdaDict if PDA
        % TO DO: check if it can be put right after addDummyComponents 
        if self.usePDA
            self.createPDAdictionary();
        end
        % Add additional controls for attack
        components = EpanetHelper.getComponents('PUMPS');
        components = cat(1,components,EpanetHelper.getComponents('VALVES'));
        components = cat(1,components,EpanetHelper.getComponents('OF_PIPES'));

        attackControls = {};
        for i = 1 : numel(components)
            thisControl = sprintf('LINK %-6s CLOSED AT TIME 999999999',components{i});
            attackControls{i,1} = thisControl;
        end

        ixControls = find(...
            cellfun(@(x) strcmp(x,'[CONTROLS]'),{sections.name}));
        sections(ixControls).text = cat(1,sections(ixControls).text,' ',attackControls);

        % close temporary file
        EpanetHelper.epanetclose();

        % add controls to temp file (used for simulations)
        EpanetHelper.createInpFileFromSections(sections,self.modifiedFilePath);
                
    end  
    
    function self = createCyberLayer(self, cybernodes, cyberlinks)
                
        % CYBERNODES        
        % check for duplicates
        if ~isequal(unique({cybernodes.name}), sort({cybernodes.name}))
            error('Duplicate names in cybernodes. Check your .cpa file.')
        end

        % get SCADA
        scadaIndex = find(ismember({cybernodes.name},'SCADA'));
        if isempty(scadaIndex)
            scadaIndex = -1;
            warning(['SCADA cybernode not found. Adding SCADA node']);         
        end

        % check PLC names
        for i = 1 :numel(cybernodes)    
            if i~=scadaIndex && strcmp(cybernodes(i).name(1:3),'PLC') == false
                error('Name of PLC node must start with "PLC"');
            end
        end

        % verify if  sensors/actuators are directly connected only to one PLC (or SCADA)
        % and all the sensors/actuators in the controls are connected to cybernodes 

        % this checks for uniqueness...
        if isequal(unique([cybernodes.sensors]), sort([cybernodes.sensors])) && ...                
            isequal(unique([cybernodes.actuators]), sort([cybernodes.actuators]))

            % ... now get all actuators and sensors in controls
            % (add P to water evels and pressures)
            sensors   = {}; actuators = {};
            for i = 1 : numel(self.controls)
                sensors = cat(2,sensors,...
                    ['P_',EpanetHelper.getComponentId(self.controls(i).nIndex, 1)]);
                actuators = cat(2,actuators,...
                    EpanetHelper.getComponentId(self.controls(i).lIndex, 0));
            end

            % ... and check if are all connected to cybernodes
            if isempty(setdiff(unique(sensors), sort([cybernodes.sensors]))) && ...                
                    isempty(setdiff(unique(actuators), sort([cybernodes.actuators])));
                % check if some specified sensors/actuators do not exists
                % sensors
                sensor_list = sort([cybernodes.sensors]);
                for i=1 : numel(sensor_list)
                    thisSensor = sensor_list{i};
                    temp = regexp(thisSensor,'_','split');
                    if temp{1} == 'P'
                        % it's a junction or a tank
                        if ~ismember(temp{2},cat(1,self.components('JUNCTIONS'),...
                                self.components('TANKS')))
                            error('Problem with %s. Component %s does not exist',thisSensor,temp{2});
                        end                        
                    elseif ismember(temp{1},['F','S','SE'])
                        % it's a pump, valve or pipe
                        if ~ismember(temp{2},cat(1,self.components('PUMPS'),...
                                self.components('VALVES'),self.components('PIPES')))
                            error('Problem with %s. Component %s does not exist',thisSensor,temp{2});
                        end                        
                    else
                        error('Variable %s not recognized',temp{1});
                    end                    
                end
                
                % actutators
                actuator_list = sort([cybernodes.actuators]);                
                if min(ismember(actuator_list,...
                        cat(1,self.components('PUMPS'),...
                        self.components('VALVES'),...
                        self.components('PIPES')))) == 0
                    error('Some actuators do not exist. Check your .cpa file.');
                end
                
                
                fprintf('PLC and controls are consistent. Check PASSED!\n');
            else
                error('Some sensors/actuators in the controls are not linked to cybernodes. Check FAILED!');                
            end
        else
            error('Sensors and actuators can only be linked to one PLC or to SCADA. Check FAILED!');                
        end

        % if all is ok, then construct cybernodes struct
        self.cyberlayer.sensors     = unique([cybernodes.sensors]);      % sensors
        self.cyberlayer.actuators   = unique([cybernodes.actuators]);    % actuators

        % PLCs
        self.cyberlayer.systems = [];      
        for i = 1 : numel(cybernodes)
            if i==scadaIndex, continue, end;
            self.cyberlayer.systems = cat(1,self.cyberlayer.systems,PLC(cybernodes(i),self.controls));    
        end  

        % SCADA (THIS NEEDS TO BE CHECKED!)
        if scadaIndex== -1
            % SCADA sees only
            self.cyberlayer.systems = cat(1,self.cyberlayer.systems,SCADA([],self.controls,self.cyberlayer.sensors));    
        else
            % SCADA does something more...
            self.cyberlayer.systems = cat(1,self.cyberlayer.systems,...
                SCADA(cybernodes(scadaIndex),self.controls,self.cyberlayer.sensors));    
        end
        
        % CYBERLINKS
        temp = [];
        for i = 1 : numel(cyberlinks)
            thisLink = cyberlinks(i);          
            cyberlinkInfo.sender = thisLink.sender;
            cyberlinkInfo.receiver = thisLink.receiver;
            for j = 1 : numel(thisLink.signals)
                cyberlinkInfo.signal = thisLink.signals{j};
                temp = [temp, Cyberlink(cyberlinkInfo)];
            end
        end        
        % check for duplicates
        if ~isequal(unique({temp.name}), sort({temp.name}))
            error('Duplicate names in cyberlinks. Check your .cpa file.')
        end
        
        self.cyberlayer.cyberlinks = temp;
        
        % check cybernodes vs cyberlinks
        for i = 1:numel(self.cyberlayer.cyberlinks)
            % check if senders are correct
            thisLink = self.cyberlayer.cyberlinks(i);
            ixSender = find(strcmp(thisLink.sender,{self.cyberlayer.systems.name}));
            if ~ismember(thisLink.signal,self.cyberlayer.systems(ixSender).sensors)
                error('%s does not read %s, so it cannot send it to %s. Check your .cpa file.',...
                    thisLink.sender,thisLink.signal,thisLink.receiver);
            end
            
            % write sensorsIn (do this better later)
            ixReceiver = find(strcmp(thisLink.receiver,{self.cyberlayer.systems.name}));
            self.cyberlayer.systems(ixReceiver) =...
                self.cyberlayer.systems(ixReceiver).addSensorIn(thisLink.signal);
        end
        
    end
    
    function self = getAllComponents(self)
        % initialize and fill the components dictionary
        componentsTypes = {...
            'TANKS','OF_TANKS','JUNCTIONS','OF_JUNCTIONS',...
            'PUMPS','VALVES','PIPES','OF_PIPES','RESERVOIRS'};

        self.components = containers.Map;
        for i = 1 : numel(componentsTypes)
            fprintf('%s\n',componentsTypes{i})
            self.components(componentsTypes{i}) = EpanetHelper.getComponents(componentsTypes{i});
        end
        
        % check that all labels are unique
        temp = cat(1,self.components.values);
        allComponents = cat(1,temp{:});
        duplicates = setdiff(allComponents,unique(allComponents));
        if ~isempty(duplicates)
            dupLabels = duplicates{1};
            for i = 2 : numel(duplicates)
                dupLables = strcat(...
                    dupLabels,sprintf('\t%s',duplicates{i}));
            end
            error('ERROR: components labels are not unique!!\n%s\n',dupLabels); 
        end
    end
    
    function [] = setDuration(self)
        patStep = single(0);
        [~,patStep] = calllib('epanet2', 'ENgettimeparam',...
            EpanetHelper.EPANETCODES('EN_PATTERNSTEP'), patStep);
        self.duration = size(self.patterns,1) * patStep;        
        calllib('epanet2', 'ENsettimeparam',...
            EpanetHelper.EPANETCODES('EN_DURATION'), single(self.duration));
    end
    
    function self = getHydraulicTimeStep(self)
        h_tstep = single(0);
        [~,h_tstep] = calllib('epanet2', 'ENgettimeparam',...
            EpanetHelper.EPANETCODES('EN_HYDSTEP'), h_tstep);
        self.h_tstep = h_tstep;
    end
    
    function [] = createPDAdictionary(self)
        junctions = keys(self.pdaDict);
        for i = 1:length(junctions)
            thisJunction = junctions{i};
            temp = self.pdaDict(thisJunction);
            % get junction, FCV and emitter indexes                
            temp.ixFCV      = EpanetHelper.getComponentIndex(['v',thisJunction]);
            temp.ixEmit     = EpanetHelper.getComponentIndex(['e',thisJunction]);
            % get pattern index
          ixPattern = EpanetHelper.getComponentValue(temp.ixJunction,1,EpanetHelper.EPANETCODES('EN_PATTERN'))            
            temp.ixPattern  = ixPattern;
            % update (in this away to avoid error "Only one level of
            % indexing...)
            self.pdaDict(thisJunction) = temp;
        end
    end 
       
    end            
end