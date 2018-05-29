classdef EpanetHelper
    % Class that contains generic functions to interface with the EPANET toolkit and 
	% modify Epanet maps. All the methods are Static so that they can be called without 
	% instantiating an object.
       
    
    %% TODO: ALL ERRORCODES (in all code) SHOULD HAVE SAME SPELLING FOR CONSISTENCY
    
    
    % Properties
    properties(Constant)
        % list of epanet parameter codes (dictionary)
        % TO DO: order them, maybe?
        EPANETCODES = containers.Map(...
            {...
            'EN_DEMAND',    'EN_HEAD',...
            'EN_PRESSURE',  'EN_FLOW',...
            'EN_STATUS',    'EN_SETTING',...
            'EN_ENERGY',    'EN_TANKLEVEL',...
            'EN_PATCOUNT',  'EN_DURATION',...
            'EN_CONTROLCOUNT', 'EN_BASEDEMAND',...
            'EN_DIAMETER',  'EN_LENGTH', 'EN_ROUGHNESS',...
            'EN_MINLEVEL','EN_MAXLEVEL',...
            'EN_REPORTSTART', ...
            'EN_NODECOUNT', 'EN_LINKCOUNT',...
            'EN_PATTERNSTEP', 'EN_HYDSTEP',...
            'EN_PATTERN', 'EN_EMITTER'},...
            [9, 10, 11, 8, 11, 12, ...
            13, 8, 3, 0, 5, 40, 0, ...
            1, 2, 20, 21, 6, 0, 2, ...
            3, 1, 2, 3]);    
    end

    % Public methods
    methods
        function self = EpanetHelper()
            % Empty constructor
        end
    end
    
    % Static methods
    methods(Static)
    
    function errorcode = epanetclose()
        % This code is modified from that of Philip Jonkergouw
        %
        % EPANETCLOSE - close the dll library 
        %
        % Syntax:  [errorcode] = epanetclose()
        %
        % Inputs:
        %    none
        % Outputs:
        %    errorcode - Fault code according to EPANET.
        %
        % Example: 
        %    [errorcode]=epanetclose()
        %        
        % Original version
        % Author: Philip Jonkergouw
        % Email:  pjonkergouw@gmail.com
        % Date:   July 2007

        % Close EPANET ...
        [errorcode] = calllib('epanet2', 'ENclose');
        if (errorcode) fprintf('EPANET error occurred. Code %g\n',...
                num2str(errorcode)); end
        if libisloaded('epanet2') unloadlibrary('epanet2'); end
    end

    function errorcode = epanetloadfile(inpFile)
        % This code is modified from that of Philip Jonkergouw and Demetrios Eliades
        %
        % EPANETLOADFILE - Loads the dll library and the network INP file.
        %
        % Syntax:  [errorcode] = epanetloadfile(inpFile)
        %
        % Inputs:
        %    inpFile - A string, name of the INP file
        %
        % Outputs:
        %    errorcode - Fault code according to EPANET.
        %
        % Example: 
        %    [errorcode]=epanetloadfile('Net1.inp')
        %
        % Original version
        % Author: Philip Jonkergouw
        % Email:  pjonkergouw@gmail.com
        % Date:   July 2007
        %
        % Minor changes by
        % Author: Demetrios Eliades
        % University of Cyprus, KIOS Research Center for Intelligent Systems and Networks
        % email: eldemet@gmail.com
        % Website: http://eldemet.wordpress.com
        % August 2009; Last revision: 21-August-2009

        %------------- BEGIN CODE --------------

        % Load the EPANET 2 dynamic link library ...
        if ~libisloaded('epanet2')
            loadlibrary('epanet2', 'epanet2.h'); 
        end

        % Open the water distribution system ...
        s = which(inpFile);
        if ~isempty(s) inpFile = s; end

        [errorcode] = calllib('epanet2', 'ENopen', inpFile, 'temp1.$$$', 'temp2.$$$');
        if (errorcode)
            error('Could not open network ''%s''.\nReturned empty array.\n', inpFile);
            return;
        else
        end
    end
        
    function list = getComponents(type)
        % Get list of Map components according to type 
        list  = {};

        nComponents = int32(0); isNode = 0;
        switch type        
            % junctions and dummy junctions (for overflow simulation)
            case {'JUNCTIONS', 'OF_JUNCTIONS'}
                [~,nComponents] =...
                    calllib('epanet2','ENgetcount',0,nComponents);
                getTypeFunction = 'ENgetnodetype';        
                componentCode = 0;
                isNode = 1;
                
            % reservoirs
            case {'RESERVOIRS'}
                [~,nComponents] =...
                    calllib('epanet2','ENgetcount',0,nComponents);
                getTypeFunction = 'ENgetnodetype';        
                componentCode = 1;
                isNode = 1;

            % tanks and dummy tanks
            case {'TANKS', 'OF_TANKS'}
                [~,nComponents] =...
                    calllib('epanet2','ENgetcount',0,nComponents);
                getTypeFunction = 'ENgetnodetype';        
                componentCode = 2;
                isNode = 1;
            
            % pipes and dummy pipes (overflow)
            case {'PIPES','OF_PIPES'}
                [~,nComponents] =...
                    calllib('epanet2','ENgetcount',2,nComponents);
                getTypeFunction = 'ENgetlinktype';
                componentCode = 1;
           
            % pumps 
            case 'PUMPS'
                [~,nComponents] =...
                    calllib('epanet2','ENgetcount',2,nComponents);
                getTypeFunction = 'ENgetlinktype';
                componentCode = 2;

            % valves
            case 'VALVES'
                [~,nComponents] =...
                    calllib('epanet2','ENgetcount',2,nComponents);
                getTypeFunction = 'ENgetlinktype';
                componentCode = 3:8;

            otherwise
                error('Search for RESERVOIRS, TANKS, OF_TANKS, JUNCTIONS, OF_JUNCTIONS, PUMPS, VALVES, PIPES, OF_PIPES or all. No %s',type);
        end

        componentType = int32(0);
        for i = 1 : nComponents        
            % retrieve component type
            index = int32(i);        
            [~,componentType] =...
                calllib('epanet2',getTypeFunction,index,componentType);

            if ismember(componentType,componentCode)
                % found component, retrieve its id
                [id,~] = EpanetHelper.getComponentId(index,isNode); 

                % This part of code is to tell apart normal components from
                % dummy components according to how they are named.
                if strcmp('TANKS',type) 
                    % storage tanks
                    if numel(id) >= 2 && ~strcmp(id(1:2),'OF')
                        list = cat(1,list,id);
                    end
                elseif strcmp('OF_TANKS',type) 
                    % dummy tanks
                    if numel(id) >= 2 && strcmp(id(1:2),'OF')
                        list = cat(1,list,id);
                    end
                elseif strcmp('JUNCTIONS',type) 
                    % junctions
                    if numel(id) >= 2 && strcmp(id(1),'J')
                        list = cat(1,list,id);
                    end
                elseif strcmp('OF_JUNCTIONS',type) 
                    % dummy junctions
                    if numel(id) >= 3 && strcmp(id(1:3),'OFj')
                        list = cat(1,list,id);
                    end            
                elseif strcmp('PIPES',type)
                    % pipes
                    if numel(id) >= 3 && ~strcmp(id(1:3),'OFp')
                        list = cat(1,list,id);
                    end
                elseif strcmp('OF_PIPES',type)
                    % dummy pipes
                    if numel(id) >= 3 && strcmp(id(1:3),'OFp')
                        list = cat(1,list,id);
                    end
                else
                    % reservoirs, valves and pumps
                    list = cat(1,list,id);
                end        
            end
        end            
    end
    
    function sections = addDummyTanks(tanks, sections)
        % Add dummy tanks to epanet .inp file to simulate overflow.
        % TO DO: not properly tested.

        % cycle through all the links and find pipes connected to tanks                
        nLinks = int32(0); 
        [errorcode, nLinks] = calllib('epanet2', 'ENgetcount', 2, nLinks); % get number of links
        
        node1 = int32(0); node2 = int32(0); % initialize nodes at link's ends
        
        for i = 1 : nLinks
            % current link
            thisLink = int32(i);
            
            % get nodes connected to link
            [~, node1,node2] = calllib(...
                'epanet2', 'ENgetlinknodes', thisLink, node1,node2);
            ID1 = EpanetHelper.getComponentId(node1,1);
            ID2 = EpanetHelper.getComponentId(node2,1);

            % check if there is a tank, if so then store tank ID and the ID
            % of the connecting junction
            if ismember(ID1,tanks)        
                thisTank  = ID1;
                thisJunc  = ID2;
            elseif ismember(ID2,tanks)
                thisJunc  = ID1;
                thisTank  = ID2;
            else
                % no tank connected, skip
                continue;
            end
            
            % create labels if there is a tank
            OFtank = ['OF', thisTank];
            OFjunc = ['OFj',thisTank];

            % add lines to sections
            
            % [COORDS]            
            sectionIx = find(cellfun(@(x) strcmp(x,'[COORDINATES]'),{sections.name})); % get section index
            coordLine = EpanetHelper.findLineInSection(...
                sections(sectionIx),thisTank);  % find tank coordinates (for placing dummy tank on the map)

            % extend section with additional lines      
            sections(sectionIx).text = cat(1,sections(sectionIx).text,...
                sprintf(' %s\t %3.3f\t %3.3f\t;',...
                OFtank,str2double(coordLine{2})+10,str2double(coordLine{3})+10)); % dummy tank coords line

            sections(sectionIx).text = cat(1,sections(sectionIx).text,...
                sprintf(' %s\t %3.3f\t %3.3f\t;',...
                OFjunc,str2double(coordLine{2})+10,str2double(coordLine{3})));    % dummy junction coords line
            
            % [JUNC]
            sectionIx = find(cellfun(@(x) strcmp(x,'[JUNCTIONS]'),{sections.name})); % get section index
        
            % extend section with additional lines  
            sections(sectionIx).text = cat(1,sections(sectionIx).text,...
                sprintf(' %s\t %d\t %d\t %s\t;',...
                OFjunc,0,0,' '));

    
            % [TANKS]
            sectionIx = find(cellfun(@(x) strcmp(x,'[TANKS]'),{sections.name})); % get section index
   
            % extend section with additional lines  
            sections(sectionIx).text = cat(1,sections(sectionIx).text,...
                sprintf(' %s\t %d\t %d\t %d\t %d\t %3.3f\t %d\t %s\t;',...
                OFtank,0,0,0,1,2*sqrt(1/pi)*10^3,0,' '));

            % [PIPES]
                            
            % get existing pipe settings            
            pDiam   = EpanetHelper.getComponentValue(thisLink, 0, EpanetHelper.EPANETCODES('EN_DIAMETER'));
            pLength = EpanetHelper.getComponentValue(thisLink, 0, EpanetHelper.EPANETCODES('EN_LENGTH'));
            pRough  = EpanetHelper.getComponentValue(thisLink, 0, EpanetHelper.EPANETCODES('EN_ROUGHNESS'));
            
            sectionIx = find(cellfun(@(x) strcmp(x,'[PIPES]'),{sections.name})); % get section index
        
            % extend section with additional lines                     
            OFp = ['OFp',thisTank];   % twin pipe label
            sections(sectionIx).text = cat(1,sections(sectionIx).text,...
                sprintf(' %s\t %s\t %s\t %0.3f\t %0.3f\t %0.3f\t %d\t %s\t;',...
                OFp, thisJunc, OFjunc, pLength, pDiam, pRough, 0,'Closed'));    % twin pipe                                      
            
            CVp = ['CVp',thisTank]; % name of CV pipe connecting to dummy tank
            sections(sectionIx).text = cat(1,sections(sectionIx).text,...
                sprintf(' %s\t %s\t %s\t %0.3f\t %0.3f\t %0.3f\t %d\t %s\t;',...
                [CVp,'b'],OFjunc,OFtank,1,pDiam,pRough,0,'CV')); % CV pipe     
        end


    end
    
    function [sections, pdaDict] = addDummyComponents(components,sections,P_min)
        % Add artificial string of FCV, CV and emitter to embed head-flow relationship

        % temp emitter coeff/FCV setting
        tempSetting = 1.0;

        % initialize       
        linesToAdd_COORDS = cell(2*numel(components),1); %1 junction, 1 emitter node
        linesToAdd_JUNCS  = cell(2*numel(components),1);
        linesToAdd_EMITS  = cell(numel(components),1);
        linesToAdd_PIPES  = cell(numel(components),1); 
        linesToAdd_VALVES  = cell(numel(components),1);  

        nNodes = numel(components);

        % get section indexes 
        ixJuncs = find(...
            cellfun(@(x) strcmp(x,'[JUNCTIONS]'),{sections.name}));       
        ixCoord = find(...
            cellfun(@(x) strcmp(x,'[COORDINATES]'),{sections.name}));
        ixValves = find(...
            cellfun(@(x) strcmp(x,'[VALVES]'),{sections.name}));
        ixEmits = find(...
            cellfun(@(x) strcmp(x,'[EMITTERS]'),{sections.name}));  %emitters section will probably be empty, but that's okay
        ixPipes = find(...
            cellfun(@(x) strcmp(x,'[PIPES]'),{sections.name}));

        % cycle through all the nodes and find nonzero demand nodes
        nCount = 0; 
        
        % add string of artificial components only if demand > 0  
        pdaDict = containers.Map();
        EN_BASEDEMAND = 1;

        for i = 1 : nNodes
            % current node
            thisNodeIndex = int32(i);
            thisNode = EpanetHelper.getComponentId(thisNodeIndex,true);
            
            thisDemand   = EpanetHelper.getComponentValue(thisNodeIndex, 1, EN_BASEDEMAND);
            % skip if base demand == 0
            if thisDemand == 0
                continue
            end
            
            % Store demand and node index. Put Placeholder for artificial components, to be filled
            % later with indexes for PDA settings update.
            temp.baseDemand = thisDemand;            
            temp.ixJunction = thisNodeIndex;
            temp.ixFCV = -1; temp.ixEmit = -1; temp.ixPattern = -1;
            pdaDict(thisNode) = temp;            

            % get existing node values
            EN_ELEVATION = 0;
            thisElev   = EpanetHelper.getComponentValue(thisNodeIndex, 1, EN_ELEVATION);

            % create additional lines for the .inp file            
            nCount = nCount + 1;
            % [COORDS]
            % find node coordinates (for placing new junction and emitter node on the map)
            coordLine = EpanetHelper.findLineInSection(sections(ixCoord),thisNode);
            PDjunc = ['j',thisNode];  % names the new artificial junction. Keep the name short to prevent stability issues. 
            PDemit = ['e', thisNode]; % names the new artificial emitter node.

            % lines to add in ".inp" file
            linesToAdd_COORDS{(nCount-1)*2+1} = ...
                sprintf(' %s\t %3.3f\t %3.3f\t;',...
                PDjunc,str2double(coordLine{2})+20,str2double(coordLine{3}));      

            linesToAdd_COORDS{nCount*2} = ...
                sprintf(' %s\t %3.3f\t %3.3f\t;',...
                PDemit,str2double(coordLine{2})+40,str2double(coordLine{3}));

            % [JUNC]
            % line to add in ".inp" file
            linesToAdd_JUNCS{(nCount-1)*2+1} = ...
                sprintf(' %s\t %d\t %3.3f\t %s\t;',...
                PDjunc,(thisElev+P_min),0,' ');

            linesToAdd_JUNCS{nCount*2} = ...
                sprintf(' %s\t %d\t %3.3f\t %s\t;',...
                PDemit,(thisElev+P_min),0,' '); % elevation is set at the nodal elevation + P_min to account for possible nonzero P_min

            % [EMITTERS]
            % line to add in ".inp" file            
            linesToAdd_EMITS{nCount} = ...
                sprintf(' %s\t %3.3f\t %s\t;',...
                PDemit,tempSetting,' ');

            % [VALVES]
            % name of FCV new junction to new emitter
            PDv = ['v',thisNode];

            pDiam = 100; %Arbitrary value. Because valves have no minor losses, I think this value shouldn't affect anything
            linesToAdd_VALVES{nCount} = ...
                sprintf(' %s\t %s\t %s\t %3.3f\t %s\t %3.3f\t %3.3f\t;',...    
                PDv,PDjunc,PDemit,pDiam,'FCV',tempSetting,0);                % need to set the FCV setting to the base demand * the pattern

            % [PIPES]
            PDp = ['p',thisNode];

            % use generic values
			% TO DO: this should be down by maybe checking the values of original pipes connected to junction, or can be specified in .cpa file
            EN_DIAMETER = 0; EN_LENGTH = 1; EN_ROUGHNESS = 2;
            pDiam   = 50.8 ;%EpanetHelper.getComponentValue(thisLink, 0, EN_DIAMETER);
            pLength = 0.001 ;% EpanetHelper.getComponentValue(thisLink, 0,EN_LENGTH);
            pRough  = 140 ;%EpanetHelper.getComponentValue(thisLink, 0,EN_ROUGHNESS);

            % line to add in ".inp" file
            linesToAdd_PIPES{nCount} = ...
                sprintf(' %s\t %s\t %s\t %0.3f\t %0.3f\t %0.3f\t %d\t %s\t;',...
                PDp,thisNode,PDjunc,...
                pLength,pDiam,pRough,0,'CV');    % zero minor losses           
        end

        % extend sections with additional lines
        % [COORDS]
        sections(ixCoord).text = cat(1,sections(ixCoord).text,linesToAdd_COORDS);

        % [JUNCS]
        sections(ixJuncs).text = cat(1,sections(ixJuncs).text,linesToAdd_JUNCS);

        % [EMITTERS]
        sections(ixEmits).text = cat(1,sections(ixEmits).text,linesToAdd_EMITS);

        % [VALVES]
        sections(ixValves).text = cat(1,sections(ixValves).text,linesToAdd_VALVES);

        % [PIPES]
        sections(ixPipes).text = cat(1,sections(ixPipes).text,linesToAdd_PIPES);       
    end
    
    function [] = createInpFileFromSections(sections,inpFile)
        % Creates EPANET input file from section structarray
        
        % open file (write)
        fileId = fopen(inpFile,'w');
        for i = 1 : numel(sections)
            if i > 1
                % add space
                fprintf(fileId, '\n\n');
            end

            % write section name
            fprintf(fileId, '%s\n', sections(i).name);

            % insert section text
            nLines = numel(sections(i).text);
            for j = 1 : nLines
                thisLine = sections(i).text{j};
                fprintf(fileId, '%s\n', thisLine);
            end
        end
        fclose(fileId);
    end
    
    function sections = divideInpInSections(inpFile)
        % Reads a .inp file and divides it into sections
        
        fileId = fopen(inpFile);
        sections = [];
        thisSection = [];
        while ~feof(fileId)
            thisLine   = fgetl(fileId);
            temp = regexp(thisLine,'\[(.*?)\]','match');
            if ~isempty(temp)

                % add previous section
                sections = cat(1,sections,thisSection);

                % start of a section
                thisSection.name = temp{1};       
                thisSection.text = {};
            else
                % add text to section
                thisSection.text = cat(1,thisSection.text,thisLine);
            end
        end
        % add last section
        sections = cat(1,sections,thisSection);
        fclose(fileId);
    end
    
    function line = findLineInSection(section, id)
        % retrieves line in a [SECTION] pertaining to a given component (id)
        text = section.text;
        nLines = numel(text);
        line = {};
        for i = 1 : nLines
            thisLine = text{i};
            temp = regexp(strtrim(thisLine),'\s*','split');
            if strcmp(temp{1},id)
                line = temp;
                return;
            end
        end

        if isempty(line)
            error('COMPONENT NOT FOUND IN SECTION TEXT');
        end
    end
        
    function [id,errorcode] = getComponentId(index,isNode)
        % Get the ID of an EPANET component, whether node or link

        % initialize
        index = int32(index);
        id = '';
        if isNode 
            [errorcode,id] =...
                    calllib('epanet2', 'ENgetnodeid', index, id);
        else
            [errorcode,id] =...
                calllib('epanet2', 'ENgetlinkid', index, id);   
        end
    end        
    
    function [index,errorcode,isNode] = getComponentIndex(id)
        % Get the index of an EPANET component, whether node or link

        isNode = true;
        [errorcode,id,index] = calllib('epanet2', 'ENgetnodeindex', id, 0);

        if errorcode
            % ... maybe is a link
            [errorcode,~,index] = calllib('epanet2', 'ENgetlinkindex', id, 0);
            isNode = false;
        end
    end
    
    function [value, errorcode] = getComponentValue(index, isNode, code)
        % Get values (according to code) of node or link

        % check if is a node
        value = single(0);
        if isNode
            [errorcode,value] = ...
                calllib('epanet2', 'ENgetnodevalue',...
                int32(index), code, value);
        else
            [errorcode,value] = ...
            calllib('epanet2', 'ENgetlinkvalue',...
            int32(index), code, value);   
        end
    end
    
    function errorcode = setComponentValue(index, value, code)
        % Set values (according to code) of node or link
        
        % set value, try node first
        errorcode = calllib('epanet2', 'ENsetnodevalue',...
            int32(index), code, value);
        
        if errorcode
            % ... maybe is a link
            errorcode = calllib('epanet2', 'ENsetlinkvalue',...
            int32(index), code, value);
        end
                         
    end      
    
    function errorcode = setPattern(index, multipliers)        
        % set the pattern identified by index
        pPointer  = libpointer('singlePtr',multipliers);
        pLength   = length(multipliers);
        errorcode = calllib('epanet2','ENsetpattern',...
            int32(index),pPointer,int32(pLength));
    end
    
    function pattern = getPattern(index)        		
        % get pattern length
        P_length = int32(0);
        [~,P_length] = calllib('epanet2', 'ENgetpatternlen',index, P_length);
        P_length = int32(P_length);
        % loop to fill pattern array
        pattern = zeros(1,P_length); 
        for i = 1 : P_length        % CHECK IF it starts from 0 or 1
            PM_value = double(0);
            [~,PM_value] = calllib('epanet2', 'ENgetpatternvalue',index, i, PM_value);
            pattern(i) = PM_value;            
        end
    end
    
    function value = getComponentValueForAttacks(id)
            % returns sensor reading for selected component 
            % i.e. Tank = water level, Pipe = flow rate, junction = pressure
            
            % get index and type
            [index,errorcode,isNode] = EpanetHelper.getComponentIndex(id);

            if ~errorcode
                % check if is a node or link
                if isNode
                    %% NODE
                    % is it a junction, reservoir or tank?
                    nodeType = int32(0);
                    [~,nodeType] = calllib('epanet2','ENgetnodetype',index,nodeType);
                    % retrieve value         
                    value = single(0);
                    switch nodeType
                        case 0
                            % junction --> PRESSURE
                            [~,value] = calllib(...
                                'epanet2','ENgetnodevalue',index,EpanetHelper.EPANETCODES('EN_PRESSURE'),value);
                        case 1
                            % reservoir --> HEAD
                            [~,value] = calllib(...
                                'epanet2','ENgetnodevalue',index,EpanetHelper.EPANETCODES('EN_HEAD'),value);
                        case 2
                            % tank --> Water level
                            [~,value] = calllib(...
                                'epanet2','ENgetnodevalue',index,EpanetHelper.EPANETCODES('EN_PRESSURE'),value);
                    end
                else
                    %% LINK
                    % is it a pipe, pump or valve?
                    % actually doesn't matter, just return the flow rate       
                    % retrieve value
                    value = single(0);
                    [~,value] = calllib(...
                        'epanet2','ENgetlinkvalue',index,EpanetHelper.EPANETCODES('EN_FLOW'),value);
                end        
            else    
                error('ERROR %d returned', errorcode);    
            end
        end
    
    %% END OF CLASS
    end    
end
