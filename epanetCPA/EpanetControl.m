classdef EpanetControl
    % Class implementing an EPANET control.
	
    properties
        isActive        % yes or no
        % TODO: these two should be accessed with a method maybe... 
        lSetting        % setting of link being controlled
        nSetting        % setting of the controlling node
    end

    properties (SetAccess = private)
        cIndex          % index of control in .inp file
        cType           % control type (0 BELOW, 1 ABOVE, ...)
        lIndex          % index of link being controlled
        nIndex          % index of the controlling node
        controlString   % string version of the control        
    end

    
    % public methods
    methods
    
    % constructor
    function self = EpanetControl(cIndex)
        % creates the control instance from the cIndex in the .inp file
        
        % initialize variables
        self.cIndex   = int32(cIndex); 
        self.cType    = int32(0); 
        self.lIndex   = int32(0); 
        self.nIndex   = int32(0); 
        self.lSetting = single(0); 
        self.nSetting = single(0);
        
        self.isActive = false;
   
        % summon .dll
        [errorcode,self.cType,self.lIndex,...
            self.lSetting,self.nIndex,self.nSetting] =...
            calllib('epanet2','ENgetcontrol',...
            self.cIndex,self.cType,self.lIndex,...
            self.lSetting,self.nIndex,self.nSetting);
    
        % create controlString
        self = self.createControlString();
    end
        
    % activate control
    function self = activate(self)
        % activate the control        
        self.isActive = true;
    end
       
    function self = deactivate(self)
        % deactivate the control (lIndex = 0)
        % summon .dll
        errorcode =...
            calllib('epanet2','ENsetcontrol',...
            self.cIndex,self.cType,int32(0),...
            self.lSetting,self.nIndex,self.nSetting);        
        self.isActive = false;
    end
    
    function self = deactivateWithValues(self,time)
        % deactivate the control (lIndex = 0)
        % summon .dll
        errorcode =...
            calllib('epanet2','ENsetcontrol',...
            self.cIndex,self.cType,self.lIndex,...
            single(0),self.nIndex,single(time));                
        self.isActive = false;
    end
    
    function self = activateWithValues(self,value,time)        
       % activates control with external value (for dummy ones)
        errorcode =...
            calllib('epanet2','ENsetcontrol',...
            self.cIndex,self.cType,self.lIndex,...
            single(value),self.nIndex,single(time));        
        
        self.isActive = true;
    end
    
    function controlString = getControlString(self)        
        [~,controlString] = self.createControlString();    
    end
    
    function self = overrideControl(self, symbolDict)
        % create override control string based on type of attack
        % TO DO: should we override only when attacks are in place to speed up computation?

        % TO DO: the control string can be determined at the beginning 
		% and updated only for the setting, so we remove the switch
        HOURS_TO_SECONDS = 3600;
                        
        switch self.cType
            case 0
                % BELOW                
                % get sensor ID
                thisSensor = EpanetHelper.getComponentId(self.nIndex, 1);       
                % create string
                overrideControlString = sprintf('symbolDict(''%s'') <= %f;',...
                    thisSensor,self.nSetting);
            case 1
                % ABOVE
                % get sensor ID
                thisSensor = EpanetHelper.getComponentId(self.nIndex, 1);       
                % create string
                overrideControlString = sprintf('symbolDict(''%s'') > %f;',...
                    thisSensor,self.nSetting);
            case 2
                % TIME IN THE SIMULATION
                % get sensor ID
                thisSensor = 'TIME';       
                overrideControlString = sprintf('symbolDict(''TIME'') == %d;',...
                    self.nSetting/HOURS_TO_SECONDS);
            case 3
                % CLOCKTIME
                % create string
                thisSensor = 'CLOCKTIME';
                overrideControlString = sprintf('symbolDict(''TIME'') == %d;',...
                    self.nSetting);
        end
        
        % create variable from dictionary
		% TO DO: remove this check when fully tested!
        try
            eval(sprintf('%s = symbolDict(''%s'');', thisSensor, thisSensor));
        catch
            error('Failed creating variable from dictionary.')
        end

        % eval string and perform action
        if eval(overrideControlString)
            % change status of actuator
             errocode = calllib('epanet2','ENsetlinkvalue',...
                 int32(self.lIndex), EpanetHelper.EPANETCODES('EN_STATUS'), single(self.lSetting>0));  
        end
    end
    
    end
    
    
    % private methods
    methods (Access = private)

    function self = createControlString(self)
        switch self.cType
            case 0
                % BELOW                
                self.controlString = sprintf(...
                    'LINK %s %.3f IF %s BELOW %.3f',...
                    EpanetHelper.getComponentId(self.lIndex,0),double(self.lSetting),...
                    EpanetHelper.getComponentId(self.nIndex,1),double(self.nSetting));
            case 1
                % ABOVE
                self.controlString = sprintf(...
                    'LINK %s %.3f IF %s ABOVE %.3f',...
                    EpanetHelper.getComponentId(self.lIndex,1),double(self.lSetting),...
                    EpanetHelper.getComponentId(self.nIndex,0),double(self.nSetting));
            case 2
                % TIME IN THE SIMULATION
                self.controlString = sprintf(...
                    'LINK %s %.3f AT TIME %.3f',...
                    EpanetHelper.getComponentId(self.lIndex,0),double(self.lSetting),...
                    double(self.nSetting));
            case 3
                % CLOCKTIME
                self.controlString = sprintf(...
                    'LINK %s %.3f AT CLOCKTIME %.3f',...
                    EpanetHelper.getComponentId(self.lIndex,1),...
                    double(self.lSetting),double(self.nSetting));
        end
    end
        
    end
    
end