
classdef EpanetCPA
    % Main class for epanetCPA.
    
    properties        
        simulation % EpanetCPASimulation instance;
        
        inpFile    % .inp file of epanet map;
        
        cpaFile    % .cpa file with info on cyber layer and attacks;
        
        cybernodes      % stores info on cyber network of sensors, actuators, plcs and SCADA
        cyberattacks    % list of cyber-physical attacks featured in the simulation
        cyberoptions    % options for epanetCPA run
    end
    
    
    % public methods
    methods
        
    function self = EpanetCPA(inpFile, cpaFile, varargin)        
        % Constructor class for EpanetCPASimulation.
        %
        % Usage:
        % 
        % EpanetCPA(inpFile, cpaFile, varargin)
        % 
        % where
        %
        % > inpFile         is the .inp file for creating the EpanetCPAMap object
        % > cpaFile         is the .cpa file containing the CPA additional parameters
        % > varargin{1}     is a boolean for specifying if simulation has attacks
        % > varargin{2}     is a boolean for enabling PDA simulations
		% 
		% If varargin is empty, attacks and PDA are inferred from .cpa file
        %
        % Returns an EpanetCPA object.
        %
        
        % store input files
        self.inpFile =  inpFile;        
        self.cpaFile =  cpaFile;
        
        % only want 2 optional inputs at most
        numvarargs = length(varargin);
        if (numvarargs ~= 0) && (numvarargs ~= 2)
            error('EpanetCPA requires at most 2 optional inputs');
        end
        
        % parse .cpa file
        [self, optargs] = self.readCpaFile();
                
        % overwrite the optargs specified in varargin.
        optargs(1:numvarargs) = varargin;

        % get flags from optional args
        [ATTACKS_ENABLED, PDA_ENABLED] = optargs{:};
        
        % create Map
        theMap = EpanetCPAMap(inpFile, self.cybernodes, self.cyberoptions, PDA_ENABLED);                

        if ATTACKS_ENABLED
            % create and run simulation with attacks
            self.simulation = EpanetCPASimulation(...
                theMap,self.cyberattacks,self.cyberoptions);
        else
            % create and run simulation with no attacks
            self.simulation = EpanetCPASimulation(...
                theMap,[],self.cyberoptions);
        end
    end
    
    function self = run(self)
        self.simulation = self.simulation.run();
    end
    
    function [] = outputResults(self, filename_prefix)

        % Ground truth values
        filename = [filename_prefix,'.csv'];
        fprintf('Writing %s (ground truth).\n',filename)
        % get header and data
        [header,table] = self.prepareDataForOutput();
        % write header to file
        fid = fopen(filename,'w'); 
        fprintf(fid,'%s\n',header);
        fclose(fid);
        % write data to end of file
        dlmwrite(filename,table,'-append','precision','%10.4f');
        
        % If any, write altered readings
        if ~isempty(self.simulation.alteredReadings)
            filename = [filename_prefix,'_altered_readings.csv'];
            fprintf('Writing %s (altered readings).\n',filename)                                   
            % open file
            fid = fopen(filename,'w'); 
            % write header to file
            header = {'timestamp','layer','sensor','reading','variable'};
            % rework header
            header = [header;repmat({','},1,numel(header))];
            header = header(:)';
            header = cell2mat(header(1:end-1));
            fprintf(fid,'%s\n',header);
            % write data
            for i = 1 : size(self.simulation.alteredReadings,1)
                thisEntry = self.simulation.alteredReadings(i);
                line = {num2str(thisEntry.time),...
                    thisEntry.layer, thisEntry.sensorId,...
                    num2str(thisEntry.reading),thisEntry.variable};
                % rework header
                line = [line;repmat({','},1,numel(line))];
                line = line(:)';
                line = cell2mat(line(1:end-1));
                fprintf(fid,'%s\n',line);
            end
            fclose(fid);
        end
    end
        
    % end of public methods
    end
    
    % private methods
    methods (Access = private)
     
    % this reads network.cpa file
    function [self, optargs] = readCpaFile(self)
        % reads content
        fileId = fopen(self.cpaFile);
        sections = [];
        thisSection = [];
        while ~feof(fileId)
            thisLine   = fgetl(fileId);
            temp = regexp(thisLine,'\[(.*?)\]','tokens');        
            if ~isempty(temp)
                section_name = temp{1}{1};

                % add previous section
                sections = cat(1,sections,thisSection);

                % start of a section
                thisSection.name = section_name;       
                thisSection.text = {};
            else
                % add text to section
                thisSection.text = cat(1,thisSection.text,thisLine);
            end
        end
        % add last section
        sections = cat(1,sections,thisSection);
        fclose(fileId);

        % iterate sections and retrieve cyber info
        for i = 1 : numel(sections)
            % TO DO: insert control if some sections are not specified!
            section_name = sections(i).name;
            section_text = sections(i).text;
            switch section_name
                case 'CYBERNODES'

                    % TO DO: should IDEALLY raise error if first line doesn't start with ; (header)                

                    if size(section_text,1) == 1
                        % EXIT< no cybernodes has been defined
                        error('ERROR: no cybernodes defined in %s. Did you include the header for this section?', cpaFile)
                    end

                    % TO DO: should IDEALLY initialize cybernodes structarray                

                    % initialize array of cybernodes
                    cybernodes = [];
                    % loop through all cybernodes
                    for j = 2 : size(section_text,1)

                        % check if comment first...
                        temp = strtrim(section_text{j});
                        if temp(1)~= ';'
                            % get \t separator positions
                            temp = regexp(section_text{j},'\t');
                            nsep = numel(temp);                            
                            if isempty(temp)
                                error('Cybernode string %d in %s file has no details.', j-1, self.cpaFile);
                            elseif nsep > 2                                
                                error('Problem with format of cybernode string %d in %s file. Check README.md',...
                                    j-1, self.cpaFile);                                                            
                            else

                                % initialize cybernode struct
                                thisNode.name = strtrim(section_text{j}(1:temp(1)));
                                thisNode.sensors     = {};
                                thisNode.actuators   = {};

                                % extend separator array if < 3 to avoid error in
                                % following section
                                if nsep < 2
                                    temp(nsep+1:3) = length(section_text{j});
                                end

                                % get sensors...
                                sensors = strtrim(section_text{j}(temp(1):temp(2)));
                                
                                if ~isempty(sensors)
                                    sensors = regexp(sensors,',','split');
                                end
                                
                                for k = 1 : numel(sensors)
                                    thisNode.sensors(k) = strtrim(sensors(k));
                                end
                                
                                % ... actuators...
                                if temp(2) ~= length(section_text{j})
                                    actuators = strtrim(section_text{j}(temp(2):end));
                                    if ~isempty(actuators)
                                        actuators = regexp(actuators,',','split');
                                    end        
                                    
                                    for k = 1 : numel(actuators)
                                        thisNode.actuators(k) = strtrim(actuators(k));
                                    end
                                end
                                
                                % concatenate
                                cybernodes = cat(1,cybernodes,thisNode);
                            end
                        end                        
                    end
                    
                case 'CYBERLINKS'            
                    warning('THIS WILL BE REMOVED!')

                case 'CYBERATTACKS'            
                    % TO DO: should IDEALLY raise error if first line doesn't start with ; (header)                
                    if size(section_text,1) == 0
                        % EXIT< no cyberattacks have been defined
                        warning('WARNING: no cyberattacks defined in %s. Did you include the header for this section?', cpaFile)
                    end
                    
                    % initialize 
                    cyberattacks = [];

                    % TO DO: should IDEALLY initialize cyberattacks structarray 
                    % loop through all cyberattacks
                    for j = 2 : size(section_text,1)
                        % check if comment first...
                        temp = strtrim(section_text{j});
                        if temp(1)~= ';'
                            % get \t separator positions
                            temp = regexp(section_text{j},'\t');
                            nsep = numel(temp);
                            if nsep ~= 4
                                disp(section_text{j}); 
                                error('Problem with format of cyberattack %d string in %s file', j-1, self.cpaFile);
                            end

                            % fill cybernode struct
                            text = section_text{j};
                            thisAttack.type       = strtrim(text(1:temp(1)));   
                            thisAttack.target     = strtrim(text(temp(1):temp(2)));   
                            thisAttack.init_cond  = strtrim(text(temp(2):temp(3)));
                            thisAttack.end_cond   = strtrim(text(temp(3):temp(4)));                    
                            % get arguments (comma separated)
                            thisAttack.arguments  = {};
                            args = regexp(strtrim(text(temp(4):end)),',','split');                        
                            for k = 1 : numel(args)
                                thisAttack.arguments(k) = strtrim(args(k));
                            end
                            
                            % copncatenate
                            cyberattacks = cat(1,cyberattacks,thisAttack);
                        end                            
                    end                    

                 case 'CYBEROPTIONS'            
                    % define default values
                    cyberoptions.verbosity = 1;
                    cyberoptions.what_to_store = {{'everything'},{},{}};
                    cyberoptions.initial_conditions = [];                    
                    cyberoptions.patterns = [];
                    cyberoptions.pda_options = [];
                    
                    
                    % loop through all cyberoptions
                    for j = 1 : size(section_text,1)

                        % get \t separator positions
                        temp = regexp(section_text{j},'\t');
                        if isempty(temp)
                             error('Problem with format of cyberoption string #%d in %s', j, self.cpaFile);
                        end

                        nsep = numel(temp);
                        text = section_text{j};
                        option = strtrim(text(1:temp(1)));

                        switch option
                            case 'verbosity'
                                % after how many steps do you want echo on
                                % screen?
                                cyberoptions.verbosity = str2num(text(temp(1):end));
                            case 'what_to_store'                                
                                % which nodes/links and variables to store?
%                                 if nsep == 1
%                                     cyberoptions.what_to_store(1) = text(temp(1):end);
%                                 elseif nsep == 2
%                                     % all links or all nodes
%                                     cyberoptions.what_to_store(1) = text(temp(1):temp(2));
%                                     cyberoptions.what_to_store(2) = text(temp(2)+1:end);
%                                     
%                                 elseif nsep == 3
                                    temp = regexp(strtrim(text(temp(1):end)),'\t','split');                        
                                    for k = 1 : numel(temp)
                                        temp_ = regexp(temp(k),',','split');                        
                                        for kk = 1 : numel(temp_)
                                            cyberoptions.what_to_store(k,kk) = strtrim(temp_(kk));
                                        end
                                    end
%                                 else
%                                     error('Error in what_to_store option format. Check README.md')
%                                 end
                            case 'initial_conditions'
                                % initial tank conditions
                                % set of n comma separated values, where n
                                % in the number of tanks in the network
                                if nsep > 1
                                    error('Problem with format of %s cyberoption.',option);
                                else
                                    temp = regexp(strtrim(text(temp(1):end)),',','split');
                                    for k = 1 : numel(temp)
                                        cyberoptions.initial_conditions(k) = str2num(temp{k});
                                    end
                                end
                            case 'patterns_file'
                                % Absolute path of csv file containing data
                                % patterns. The file has number of rows
                                % equal to the total steps of the
                                % simulation and number of columns equal to
                                % the number of patterns specified in the
                                % .inp file.
                                if nsep > 1
                                    error('Problem with format of %s cyberoption.',option);                                    
                                else
                                    filename = text(temp(1):end);
                                    cyberoptions.patterns = csvread(filename);                                    
                                end    
                            case 'pda_options'
                                if nsep ~= 4
                                    error('Problem with format of %s cyberoption.',option);                                    
                                else
                                    pda_options.emitterExponent = str2num(text(temp(1):temp(2)));
                                    pda_options.Pmin = str2num(text(temp(2):temp(3)));
                                    pda_options.Pdes = str2num(text(temp(3):temp(4)));
                                    pda_options.HFR = strtrim(text(temp(4):end));
                                    cyberoptions.pda_options = pda_options;                                    
                                end 
                            otherwise
                                if option(1)~= ';'                                    
                                    error('Option %s not recognized!',option)                    
                                end                                
                        end
                    end
                otherwise
                    error('Section %s not recognized!',section_name)
            end
        end
        
        % create cell array of attacks
        nAttacks = size(cyberattacks,1);
        attacks = cell(1,nAttacks);
        for i = 1 : nAttacks
            thisAttack = cyberattacks(i);
            eval_string = sprintf(['attacks{%d} = AttackOn%s('...
                'thisAttack.target,thisAttack.init_cond,thisAttack.end_cond,thisAttack.arguments);'],i,thisAttack.type);
            evalc(eval_string);
        end
        cyberattacks = attacks;               
        
        % modify cyberoptions.what_to_store for EpanetCPASimulation
        whatToStore.sensors  = cyberoptions.what_to_store{1};
        whatToStore.nodeVars = cyberoptions.what_to_store{2};
        whatToStore.linkVars = cyberoptions.what_to_store{3};
        cyberoptions.what_to_store = whatToStore;        

        % return
        self.cybernodes     = cybernodes;
        self.cyberattacks   = cyberattacks;
        self.cyberoptions   = cyberoptions;
        optargs = {~isempty(cyberattacks),~isempty(cyberoptions.pda_options)};
    end

    function [header,table] = prepareDataForOutput(self)
        % initialize   
        sim = self.simulation;
        header = {'timestamp'}; % maybe add time of the day?
        table = cat(2, sim.T);
        
        % do nodes
        if ~isempty(sim.whatToStore.nodeIdx)
            for i=1:numel(sim.whatToStore.nodeVars) 
                thisVar = sim.whatToStore.nodeVars{i};
                for j = 1 : numel(sim.whatToStore.nodeID)
                    thisNode = sim.whatToStore.nodeID{j};
                    % extend header        
                    header = cat(2,header,[thisVar,'_',thisNode]);        
                end
                table = cat(2,table,sim.readings.(thisVar));
            end
        end
        
        % do links
        if ~isempty(sim.whatToStore.linkIdx)
            for i=1:numel(sim.whatToStore.linkVars) 
                thisVar = sim.whatToStore.linkVars{i};
                for j = 1 : numel(sim.whatToStore.linkID)
                    thisLink = sim.whatToStore.linkID{j};
                    % extend header        
                    header = cat(2,header,[thisVar,'_',thisLink]);        
                end
                table = cat(2,table,sim.readings.(thisVar));      
            end
        end

        % do attack track
        for i=1:size(sim.attackTrack,2)
            header = cat(2,header,sprintf('Attack#%02d',i));                   
        end
        table = cat(2,table,sim.attackTrack);


        % rework header
        header = [header;repmat({','},1,numel(header))];
        header = header(:)';
        header = cell2mat(header(1:end-1));
    end
        
    % end of private methods
    end            
end
    