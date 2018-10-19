classdef Cyberlink
    % Class implementing a cyberlink

    properties
        name                % name (same naming used for attack targets)
        sender              % sender
        receiver            % receiver
        signal              % signal (variable) being transmitted
    end
        
    methods
    
    % constructor
    function self = Cyberlink(cyberlinkInfo)
        % creates controller instance from info
        self.name = sprintf('%s-%s-%s',...
            cyberlinkInfo.sender,cyberlinkInfo.signal,cyberlinkInfo.receiver);
        self.sender = cyberlinkInfo.sender;
        self.receiver = cyberlinkInfo.receiver;
        self.signal = cyberlinkInfo.signal;
    end
   
    % end of public methods
    end
        
end
