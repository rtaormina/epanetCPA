classdef AttackOnSensor < CyberPhysicalAttack   
    % Class implementing a physical attack to a Sensor.
    
    properties           
        alterMethod             % how are readings altered by the attack?                                 
        alteredReading          % current altered reading of the sensor            
    end
     
    % public methods
    methods
    
    function self = AttackOnSensor(...
            target, ini_condition, end_condition, args)
        
        % handle args
        alterMethod = args{1};
        setting = [];
        switch alterMethod
            case 'DoS'
                % sensor returns last trainsmitted reading
                if numel(args) > 1
                    error('Too many arguments for <DoS> AttackOnSensor')
                end                
            case 'constant'
                % subsitute reading with a constant value
                if numel(args) > 2
                    error('Too many arguments for <constant> AttackOnSensor')
                else
                    setting = str2num(args{2});
                end                
            case 'offset'                
                % adds offset to reading
                if numel(args) > 2
                    error('Too many arguments for <offset> AttackOnSensor')
                else
                    setting = str2num(args{2});
                end        
            case 'custom'                
                % substitute with custom readings
                if numel(args) == 2
                    % check if file exists
                    filename = args{2};                    
                    if ~exist(filename, 'file')
                        error(' AttackOnSensor: File containing custom altered readings cannot be found!')
                    end
                    setting = csvread(filename);
                else
                    error('Wrong number of arguments for <custom> AttackOnSensor')
                end                
            otherwise
                error('not implemented yet!')
        end
        % call superclass constructor
        self@CyberPhysicalAttack(...
            'PHY', target, ini_condition, end_condition, setting);
        % initialize other properties
        self.alterMethod    = alterMethod;
        self.alteredReading = NaN;
    end
	
    
	function self = performAttack(self, varargin)  
        % get arguments
		epanetSim 	= varargin{1};        
		% compute altered value of the sensor
		self = self.alterReading(epanetSim);
	end
    
	function self = stopAttack(self, varargin) 
		% get arguments
		time = varargin{1};
        % attack is off
        self.inplace = 0;
        self.endTime = time;                
        % reset altered reading
        self.alteredReading = NaN;
    end
    
    function [self, epanetSim] = evaluateAttack(self, epanetSim)			
        if self.inplace == 0
            % attack is not active, check if starting condition met
            flag = self.evaluateStartingCondition(epanetSim.symbolDict);            
            if flag
                % start attack
                self = self.startAttack(epanetSim.symbolDict('TIME'),epanetSim);
            end
        else
            % attack is ongoing, check if ending condition is met for this attack
            flag = self.evaluateEndingCondition(epanetSim.symbolDict);
            if flag
				% stop attack
				self = self.stopAttack(epanetSim.symbolDict('TIME'));
            else
                % ...continue attack (needed for sensor alteration)
                self = self.performAttack(epanetSim);
            end
        end  
    end
    
    end
    
    % private methods
    methods (Access = private)
          
    function self = alterReading(self, epanetSim)   
        % get time vector        
        T = epanetSim.T;
		% initialize to current time
        rowToCopyFrom = numel(T);        
        % switch alter method
        switch self.alterMethod
            case 'DoS'         
                % reading is not updated
                if isnan(self.alteredReading)
                    % assign last reading if it's first time
                    % otherwise leave unchanged. It's reset to NaN
                    % when attack ceases.                    
                    thisReading = getReading(self, rowToCopyFrom, epanetSim);  
                    self.alteredReading = thisReading;
                end
            case 'constant'
                % subsitute reading with a constant value
                self.alteredReading = self.setting;                
            case 'offset'                
                % adds offset to reading
                thisReading = getReading(self, rowToCopyFrom, epanetSim);  
                self.alteredReading = thisReading + self.setting;
            case 'custom'                
                % substitute with custom readings
                T  = epanetSim.T(end);                
                ix = find(self.setting(:,1)>=T,1);
                if ~isempty(ix)                
                    self.alteredReading = self.setting(ix,2);      
                else
                    self.alteredReading = self.setting(end,2);
                end
            otherwise
                error('not implemented yet!')
        end
    end
    
    function thisReading = getReading(self, rowToCopyFrom, epanetSim)
        
	time = epanetSim.T(rowToCopyFrom);        
        % get attacked component and index
        thisComponent = self.target;
	
	% remove prefix
        temp = regexp(thisComponent,'_','split');
        thisVariable = temp{1};
        thisComponent = temp{2};
        if ~ismember(thisVariable,'PFS')
            error('Attacks targeting %s not implemented yet.',temp{1});
        end 
	
        [thisIndex,~,isNode] = EpanetHelper.getComponentIndex(thisComponent);                
        if isNode
            thisIndex = find(ismember(epanetSim.whatToStore.nodeIdx,thisIndex));
        else            
            thisIndex = find(ismember(epanetSim.whatToStore.linkIdx,thisIndex));
        end        
        % check if variable has been stored, otherwise return error
        if isempty(thisIndex)
            error('Variable %s is not among those being stored during the simulation',...
                thisComponent);
        end
        
        % If it has been already modified, return the modified value
        % if not, return physical layer reading.
        % TO DO: check if it works in everycase
        try
            ix = find(([epanetSim.alteredReadings.time] == time) & ...
                strcmp({epanetSim.alteredReadings.layer},'PLC') & ... 
                strcmp({epanetSim.alteredReadings.sensorId},thisComponent));                       
        catch
            % TODO: should substitute this catch statement
            ix = [];
        end
		
        if ~isempty(ix) 
            thisReading = epanetSim.alteredReadings(ix).reading;
        else
            % check if it's node (if so return pressure)
            if isNode
                thisReading = epanetSim.readings.PRESSURE(rowToCopyFrom,thisIndex);
            else
                % return flow if it's a link
                thisReading = epanetSim.readings.FLOW(rowToCopyFrom,thisIndex);
            end
        end        
    end
        
    end
        
end
    
