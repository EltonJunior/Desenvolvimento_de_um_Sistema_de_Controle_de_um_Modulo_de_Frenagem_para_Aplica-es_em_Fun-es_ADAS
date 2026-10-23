classdef BrakeSerialEncoder < matlab.System
    %BRAKESERIALENCODER Builds a command line for the AURIX brake UART protocol.
    %   Mode is a block parameter (set in the dialog), not a runtime input,
    %   since it does not change every step.
    %
    %   Port: [omega, uIn, uOut] (double/uint8 scalars) -> msg (uint8 row, fixed max length)

    properties (Nontunable)
        Mode = 'ECHO' % 'ECHO' or 'LIVE'
        MaxLength = 48
    end

    methods (Access = protected)
        function [msg, len] = stepImpl(obj, omega, uIn, uOut)
            if strcmpi(obj.Mode, 'ECHO')
                text = sprintf('[ECHO]<%.2f,%u,%u>\n', omega, uint8(uIn), uint8(uOut));
            else
                text = sprintf('OMEGA_P=%.2f,U_IN=%u,U_OUT=%u\n', omega, uint8(uIn), uint8(uOut));
            end

            msg = zeros(1, obj.MaxLength, 'uint8');
            len = uint32(min(length(text), obj.MaxLength));
            msg(1:len) = uint8(text(1:len));
        end

        function [msg, len] = getOutputSizeImpl(obj)
            msg = [1 obj.MaxLength];
            len = [1 1];
        end

        function [msg, len] = getOutputDataTypeImpl(~)
            msg = 'uint8';
            len = 'uint32';
        end

        function [msgComplex, lenComplex] = isOutputComplexImpl(~)
            msgComplex = false;
            lenComplex = false;
        end

        function [msgFixed, lenFixed] = isOutputFixedSizeImpl(~)
            msgFixed = true;
            lenFixed = true;
        end
    end
end
