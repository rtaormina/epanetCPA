classdef AttackOnCommunication < CyberPhysicalAttack   
    % Class for attack targeting a communication channel between cyber components.
    
    properties        
        alterMethod             % how is the reading altered (DoS, constant,
                                % offset, custom values, replay attack)
								
        alteredReading          % current altered reading of the sensor        
		
        sender                  % starting point of the communication, can be 
                                % PHY, a PLC or SCADA
								
        receiver                % ending point of tshe communication, can be 
                                % PHY, a PLC or SCADA   
        
        targetIsSensor          % TRUE if target is a node (sensor)
                                % FALSE if it is a link (actuator). 
								% TO DO: Ideally this value should be 
                                % stored when calling constructor. At the moment,
                                % it is stored during validation instead as it
                                % needs interfacing with list of controllers.        
    end
    
    % public methods
    methods
        
    function self = AttackOnCommunication(...
            str, ini_condition, end_condition, args)
        
        % parse str (sender-target-receiver)
        temp = regexp(str,'-','split');
        if numel(temp)~= 3
            % raise error
            error('AttackOnCommunication: need to correctly specify sender-target-receiver.');
        else
            sender = temp{1}; target = temp{2}; receiver = temp{3};
        end
        
        % handle args for alteration method
        alterMethod = args{1}; 
        setting = [];
        switch alterMethod
            case 'DoS'         
                if numel(args) > 1
                    error('Too many arguments for <DoS> AttackOnCommunication')
                end                
            case 'constant'
                % subsitute reading with a constant value
                if numel(args) == 2
                    setting = str2num(args{2});
                else
                    error('Wrong number of arguments for <constant> AttackOnCommunication')                    
                end
            case 'offset'                
                % adds offset to reading
                if numel(args) == 2
                    setting = str2num(args{2});
                else
                    error('Wrong number of arguments for <offset> AttackOnCommunication')
                end        
            case 'custom'                
                % substitute with custom readings
                if numel(args) == 2
                    % check if file exists
                    filename = args{2};                    
                    if ~exist(filename, 'file')
                        error(' AttackOnCommunication: File containing custom altered readings cannot be found!')
                    end
                    setting = csvread(filename);
                else
                    error('Wrong number of arguments for <custom> AttackOnCommunication')
                end
            case 'replay'
                % replay attack
                if numel(args) ~= 5
                    error('Wrong number of arguments for <replay> AttackOnCommunication')
                else
                    setting(1) = str2num(args{2});
                    setting(2) = str2num(args{3});
                    setting(3) = str2num(args{4});
                    setting(4) = str2num(args{5});
                end
            otherwise
                error('not implemented yet!')
        end
        
		% summon superclass constructor
        layer = receiver;
        self@CyberPhysicalAttack(...
            layer, target, ini_condition, end_condition, setting);
        
        % store properties
        self.setting = setting;
        self.sender = sender;
        self.receiver = receiver;
        self.alterMethod = alterMethod;        
        
        % initialize alteredReading
        self.alteredReading = NaN;
    end
        
    function self = performAttack(self, varargin)
		% get arguments
		epanetSim 	= varargin{1};
        if self.targetIsSensor
            % alter sensor reading
            self = self.alterSensorReading(epanetSim);
        else
            % alter transmission to actuator
            self = self.alterTransmissionToActuator(epanetSim);
        end
    end
    
    function self = stopAttack(self, varargin)
		% get arguments
		time = varargin{1};
        
        % attack is off
        self.inplace = 0;
        self.endTime = time;

        % reset altered reading
        self.alteredReading = NaN;
        self.setting = [];
    end    
    
    function [self, epanetSim] = evaluateAttack(self, epanetSim)
		if self.inplace == 0
            % attack is not active, check if starting condition met
            flag = self.evaluateStartingCondition(epanetSim.symbolDict);            
            if flag
                % start attack
                self = self.startAttack(epanetSim.symbolDict('TIME'),epanetSim);                
                if ~self.targetIsSensor 
					% TO DO: should find a better way to perform dummy
					% control activation, outside of this class.
					epanetSim.epanetMap.dummyControls(self.actControl).isActive = 1;                     
                end
            end
        else
            % attack is ongoing
            % check if ending condition is met for this attack
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
    
    function self = validateAttack(self, PLCs)
        % Validate attacks, i.e. is sensor connected to that PLC?
        % TO DO: it shouldn't be a public method.
        
        % check if sender and receiver are the same
        if strcmp(self.sender,self.receiver) == 1
            error('AttackOnCommunication: sender and receiver cannot be the same.');
        end
        
        % check if target exists
        if sum(ismember(PLCs.sensors,self.target)) +...
                sum(ismember(PLCs.actuators,self.target)) == 0
            error('AttackOnCommunication: target %s does not exist.', self.target);            
        else
            self.targetIsSensor = sum(ismember(PLCs.sensors,self.target))==1;
        end
                
        % check if connection is inplace: sender has to be either PHY or have target in sensors; 
        % receiver has to be either PHY (for actuators) or have sensor in sensorsIn
        ixSender    = find(ismember({PLCs.systems.name},self.sender));
        ixReceiver  = find(ismember({PLCs.systems.name},self.receiver));
        if isempty(ixSender) && ~strcmp(self.sender,'PHY')
            error('AttackOnCommunication: sender %s does not exist.', self.sender);
        end
        
        if isempty(ixReceiver) && ~strcmp(self.receiver,'PHY')
            error('AttackOnCommunication: receiver %s does not exist.', self.receiver);
        end
        
        if self.targetIsSensor
            % target is a sensor
            if strcmp(self.sender,'PHY')
                % receiver must have sensor in his sensor list
                if sum(ismember(PLCs.systems(ixReceiver).sensors,self.target)) == 0
                    error('AttackOnCommunication: receiver %s is not linked to %s sensor.',...
                        self.receiver, self.target);
                end            
            else
                % receiver must have sensor in his sensorsIn list
                if sum(ismember(PLCs.systems(ixReceiver).sensorsIn,self.target)) == 0
                    error('AttackOnCommunication: receiver %s is not linked to %s sensor.',...
                        self.receiver, self.target);
                % and sender has to read the sensor                
                elseif sum(ismember(PLCs.systems(ixSender).sensors,self.target)) == 0
                    error('AttackOnCommunication: sender %s is not directly linked to %s sensor.',...
                        self.sender, self.target);                        
                end
				% TO DO: what to do if target is in sensorsIn of sender? 
            end       
        else   
            % target is an actuator        
            if strcmp(self.receiver,'PHY')
                % sender must have actuator in his actuator list
                if sum(ismember(PLCs.systems(ixSender).actuators,self.target)) == 0
                    error('AttackOnCommunication: sender %s is not linked to %s actuator.',...
                        self.sender, self.target);
                end  
                
                % check if alterMethod is DoS or constant (OFF=0,ON=1,values in between for speed/valve setting);
				% other alterMethods are not available when target is an actuator
				% TO DO: currently we do not check if "constant" values are between 0 and 1
                if sum(ismember({'DoS','constant'},self.alterMethod)) == 0
                    error(['AttackOnCommunication: outgoing communications',...
                        'to actuators can only be DoS-ed or altered with a constant value [0 or 1].']);
                elseif strcmp('constant', self.alterMethod)
                    % check if values are 0 or 1
                    if self.setting~=0 && self.setting~=1
                        error(['AttackOnCommunication: outgoing communications',...
                            ' to actuators can only be altered with 0 or 1'])
                    end
                end
                
            elseif strcmp(self.receiver,'SCADA')
                % we are actually reporting the FLOW of through valve or pump back to SCADA.
				% it's a sensor reading, targetIsSensor set to 1
                self.targetIsSensor = 1;
                
                % sender must have actuator in his actuator list
                if sum(ismember(PLCs.systems(ixSender).actuators,self.target)) == 0
                    error('AttackOnCommunication: sender %s is not linked to %s actuator.',...
                        self.sender, self.target);
                end  
            else
                % receiver must be PHY or SCADA
                error('AttackOnCommunication: if target is an actuator, receiver can only be PHY or SCADA.')        
            end
        end        
    end
         
    end
    
    % private methods
    methods (Access = private)
	
    function self = alterSensorReading(self, epanetSim)   
        % get time vector        
        T = epanetSim.T;
        rowToCopyFrom = numel(T); % initialize to current time

        % switch alter method
        switch self.alterMethod

            case 'DoS'         
                % reading is not updated
                if isnan(self.alteredReading)
                    thisReading = getReading(self, rowToCopyFrom, epanetSim);  
                    self.alteredReading = thisReading;
                else
                    % no need to update
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

            case 'replay'
                % replay attack

                % get parameters
                delay = self.setting(1);
                noiseIntensity = self.setting(2);
                maxValue = self.setting(3);
                minValue = self.setting(4);

                sPoint = (self.iniTime-delay); % initial copying point
                timeRef = sPoint + mod(T(end)-sPoint,delay);
                rowToCopyFrom = find(T>=timeRef,1);
                % get past reading to repeat
                thisReading = getReading(self, rowToCopyFrom, epanetSim);                   
                % only pressure and water level                                
                delta = noiseIntensity * (2*rand(1)-1);                
                if thisReading + delta > maxValue
                    self.alteredReading = maxValue;
                elseif thisReading + delta < minValue
                     self.alteredReading = minValue; 
                else
                    self.alteredReading = thisReading + delta;
                end

            otherwise
                error('not implemented yet!')
        end    
    end

    function self = alterTransmissionToActuator(self, epanetSim)   
        % get time vector        
        T = epanetSim.T;
        rowToCopyFrom = numel(T); % initialize to current time

        % switch alter method        
        if strcmp(self.alterMethod,'DoS') && isempty(self.setting)
            % DoS
            self.setting = getReading(self, rowToCopyFrom, epanetSim)>0;
        else
            % Otherwise is replaced with constant value (0, 1, or anything in between)
        end
        % Alter transmission from controller to actuator                
        % (works like AttackOnActuator)                    

        % get dummy controls
        dummyControls = epanetSim.epanetMap.dummyControls;

        % get attacked component and index                    
        thisIndex = EpanetHelper.getComponentIndex(self.target);

        % activate dummy control, save and exit        
        for i = 1 : numel(dummyControls)
            if dummyControls(i).lIndex == thisIndex
                self.actControl = i;
                return
            end  
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
        if isNode
            if isempty(epanetSim.readings.PRESSURE) || (sum(ismember(epanetSim.whatToStore.sensors, thisComponent))==0)
                error(['Cannot perform attack as PRESSURE(TANK LEVEL) variable for %s is not being stored during the simulation.\n',...
                    'Modify .cpa file accordingly and run simulation again.'],thisComponent);
            end 
        else
            if isempty(epanetSim.readings.FLOW) || (sum(ismember(epanetSim.whatToStore.sensors, thisComponent))==0)
                error(['Cannot perform attack as FLOW variable for %s is not being stored during the simulation.\n',...
                    'Modify .cpa file accordingly and run simulation again.'],thisComponent);
            end 

        end

        % if it has been already modified, return the modified value
        % if not, return physical layer reading.  
        try
            ix = find(([epanetSim.alteredReadings.time] == time) & ...
                strcmp({epanetSim.alteredReadings.layer},'PLC') & ... 
                strcmp({epanetSim.alteredReadings.sensorId},thisComponent));                       
        catch
            % TODO: should substitute this catch statement
            ix = [];
        end
		
        if ~isempty(ix) 
			% value has been altered already
            thisReading = epanetSim.alteredReadings(ix).reading;
        else
            % check if it's node (if so return pressure)
            if isNode
                thisReading = epanetSim.readings.PRESSURE(rowToCopyFrom,thisIndex);
            else
                % return flow if it's a link
                switch thisVariable
                    case 'F'
                        thisReading = epanetSim.readings.FLOW(rowToCopyFrom,thisIndex);
                    case 'S'
                        thisReading = epanetSim.readings.STATUS(rowToCopyFrom,thisIndex);
                    otherwise
                        error('How did I get here?')
                end
            end
        end        
    end
           
    end
        
end
    