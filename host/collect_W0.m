function directory=collect_W0(port)
% Receiver only. Strict4a5751a0; no controller commands.
if nargin<1,port='COM6';end
addpath(fileparts(mfilename('fullpath')),'-begin');
directory=matlab_collect_j280_w0(port,115200,120);
summarize_W0(directory);
end
