classdef BrakeSerialDecoder < matlab.System
    %BRAKESERIALDECODER Parses "[ECHO],omega,u_in,u_out,pw_psi,pos_mm,status"
    %   or "[LIVE],omega,u_in,u_out,pw_psi,pos_mm,status" lines from the AURIX.
    %
    %   Inputs: buffer (uint8, fixed max length, from the Serial Receive block),
    %           count  (uint32 scalar, number of valid bytes in buffer this step).
    %   Slicing buffer(1:count) is free here because this runs interpreted;
    %   only the block ports themselves need the fixed max length.

    methods (Access = protected)
        function [omega, uIn, uOut, pwPsi, posMm, status, valid] = stepImpl(~, buffer, count)
            omega = 0; uIn = uint8(0); uOut = uint8(0);
            pwPsi = 0; posMm = 0; status = uint8(0); valid = false;

            n = double(count);
            if (n < 1) || (n > numel(buffer))
                return;
            end
            line = char(buffer(1:n));

            headerEnd = strfind(line, ']');
            if isempty(headerEnd)
                return;
            end

            payload = strtrim(line(headerEnd(1)+1:end));
            if isempty(payload) || payload(1) ~= ','
                return;
            end
            payload = payload(2:end);

            values = sscanf(payload, '%f,%f,%f,%f,%f,%f');
            if numel(values) ~= 6
                return;
            end

            omega  = values(1);
            uIn    = uint8(values(2));
            uOut   = uint8(values(3));
            pwPsi  = values(4);
            posMm  = values(5);
            status = uint8(values(6));
            valid  = true;
        end

        function [omega, uIn, uOut, pwPsi, posMm, status, valid] = getOutputSizeImpl(~)
            omega = [1 1]; uIn = [1 1]; uOut = [1 1];
            pwPsi = [1 1]; posMm = [1 1]; status = [1 1]; valid = [1 1];
        end

        function [omega, uIn, uOut, pwPsi, posMm, status, valid] = getOutputDataTypeImpl(~)
            omega = 'double'; uIn = 'uint8'; uOut = 'uint8';
            pwPsi = 'double'; posMm = 'double'; status = 'uint8'; valid = 'logical';
        end

        function varargout = isOutputComplexImpl(~)
            varargout = {false, false, false, false, false, false, false};
        end

        function varargout = isOutputFixedSizeImpl(~)
            varargout = {true, true, true, true, true, true, true};
        end
    end
end
