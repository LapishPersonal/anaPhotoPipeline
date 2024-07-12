function [data] = SEV2mat(SEV_DIR, varargin)
%SEV2MAT  TDT SEV file format extraction.
%   data = SEV2mat(SEV_DIR), where SEV_DIR is a string, retrieves
%   all sev data from specified directory in struct format. SEV files
%   are generated by an RS4 Data Streamer, or by enabling the Discrete
%   Files option in the Synapse Stream Data Storage gizmo, or by setting
%   the Unique Channel Files option in Stream_Store_MC or Stream_Store_MC2
%   macro to Yes in OpenEx.
%
%   data    contains all continuous data (sampling rate and raw data)
%
%   data = SEV2mat(SEV_DIR,'parameter',value,...)
%
%   'parameter', value pairs
%      'T1'         scalar, retrieve data starting at T1 (default = 0 for
%                       beginning of recording)
%      'T2'         scalar, retrieve data ending at T2 (default = 0 for end
%                       of recording)
%      'CHANNEL'    integer or array, choose a single channel or array of
%                       channels to extract from sev data (default = 0 for
%                       all channels)
%      'RANGES'     array of valid time range column vectors
%      'JUSTNAMES'  boolean, retrieve only the valid event names
%      'EVENTNAME'  string, specific event name to retrieve data from
%      'VERBOSE'    boolean, set to false to disable console output
%      'DEVICE'     string, connect to specific RS4 device.  DEVICE can be
%                       the IP address or NetBIOS name of RS4-device
%                       (e.g. RS4-41001).  Requires TANK and BLOCK
%                       parameters
%      'TANK'       string, tank on RS4 to retrieve data from. Requires
%                       DEVICE and BLOCK parameters
%      'BLOCK'      string, block on RS4 to retrieve data from. Requires
%                       DEVICE and TANK parameters
%      'FS'         float, sampling rate override. Useful for lower
%                       sampling rates that aren't correctly written into
%                       the SEV header.
%

if ~mod(nargin, 2)
    error('not enough input arguments')
end

% defaults
CHANNEL   = 0;
EVENTNAME = '';
DEVICE    = '';
TANK      = '';
BLOCK     = '';
T1        = 0;
T2        = 0;
RANGES    = [];
VERBOSE   = 0;
JUSTNAMES = 0;
FS        = 0;

VALID_PARS = {'CHANNEL','EVENTNAME','DEVICE','TANK','BLOCK','T1','T2' ...
    'RANGES','VERBOSE','JUSTNAMES','FS'};

% parse varargin
for ii = 1:2:length(varargin)
    if ~ismember(upper(varargin{ii}), VALID_PARS)
        error('%s is not a valid parameter. See help SEV2mat.', upper(varargin{ii}));
    end
    eval([upper(varargin{ii}) '=varargin{ii+1};']);
end

if any([~isempty(DEVICE) ~isempty(TANK) ~isempty(BLOCK)])
    if any([isempty(DEVICE) isempty(TANK) isempty(BLOCK)])
        error('DEVICE, TANK and BLOCK must all be specified');
    else
        SEV_DIR = sprintf('\\\\%s\\data\\%s\\%s\\', DEVICE, TANK, BLOCK);
    end
end

data = [];
sample_info = [];

ALLOWED_FORMATS = {'single','int32','int16','int8','double','int64'};

xxx = exist(SEV_DIR, 'file');
singleFile = 0;
if xxx == 2
    % treat as single file only
    file_list = [dir(SEV_DIR)];
    SEV_DIR = [fileparts(SEV_DIR) filesep];
    singleFile = 1;
elseif xxx == 7
    % treat as directory 
    if strcmp(SEV_DIR(end), filesep) == 0
        SEV_DIR = [SEV_DIR filesep];
    end
    file_list = dir([SEV_DIR '*.sev']);
    
    % parse log files
    if JUSTNAMES == 0
        txt_file_list = dir([SEV_DIR '*_log.txt']);
        
        n_txtfiles = length(txt_file_list);
        if n_txtfiles < 1 && VERBOSE
            fprintf('info: no log files in %s\n', SEV_DIR);
        else
            for ii = 1:n_txtfiles
                if VERBOSE
                    fprintf('info: log file %s\n', txt_file_list(ii).name);
                end
                
                % get store name
                matches = regexp(txt_file_list(ii).name, '^[^_|-]+(?=_|-)', 'match');
                temp_sample_info = [];
                if ~isempty(matches)
                    temp_sample_info.name = matches{1};
                    txt_path = [SEV_DIR txt_file_list(ii).name];
                    fid = fopen(txt_path);
                    log_text = fscanf(fid, '%c');
                    if VERBOSE, fprintf(log_text); end
                    fclose(fid);
                    
                    t = regexp(log_text, 'recording started at sample: (\d*)', 'tokens');
                    temp_sample_info.start_sample = str2double(t{1}{1});
                    t = regexp(txt_file_list(ii).name, '-(\d)h', 'tokens');
                    if isempty(t)
                        temp_sample_info.hour = 0;
                    else
                        temp_sample_info.hour = str2double(t{1}{1});
                    end
                    
                    if temp_sample_info.start_sample > 2 && temp_sample_info.hour == 0
                        warning('%s store starts on sample %d', temp_sample_info.name, temp_sample_info.start_sample);
                    end
                    
                    % look for gap info
                    temp_sample_info.gaps = [];
                    temp_sample_info.gap_text = '';
                    gap_text = regexp(log_text, 'gap detected. last saved sample: (\d*), new saved sample: (\d*)', 'match');
                    t = regexp(log_text, 'gap detected. last saved sample: (\d*), new saved sample: (\d*)', 'tokens');
                    if ~isempty(t)
                        temp_sample_info.gaps = reshape(cell2mat(cellfun(@str2double,t,'uniform',0)), 2, []);
                        temp_sample_info.gap_text = strjoin(gap_text', '\n   ');
                        if temp_sample_info.hour > 0
                            warning('gaps detected in data set for %s-%dh!\n   %s\nContact TDT for assistance.\n', temp_sample_info.name, temp_sample_info.hour, temp_sample_info.gap_text);
                        else
                            warning('gaps detected in data set for %s!\n   %s\nContact TDT for assistance.\n', temp_sample_info.name, temp_sample_info.gap_text);
                        end
                    end
                    sample_info = [sample_info temp_sample_info];
                end
            end
        end
    end
elseif xxx == 0
    error('Unable to find sev file or directory:\n\t%s', SEV_DIR)
end

nfiles = length(file_list);
if nfiles < 1
    if VERBOSE
        fprintf('info: no sev files in %s\n', SEV_DIR);
    end
    return
end

if FS > 0
    fprintf('Using %.4f Hz as SEV sampling rate for %s\n', FS, EVENTNAME)
end
    
% find out what data we think is here
for ii = 1:length(file_list)
    [pathstr, name, ext] = fileparts(file_list(ii).name);
    
    % find channel number
    matches = regexp(name, '_[Cc]h[0-9]*', 'match');
    if ~isempty(matches)
        sss = matches{end};
        file_list(ii).chan = str2double(sss(4:end));
    end
    
    % find starting hour
    matches = regexp(name, '-[0-9]*h', 'match');
    if ~isempty(matches)
        sss = matches{end};
        file_list(ii).hour = str2double(sss(2:end-1));
    else
        file_list(ii).hour = 0;
    end
    
    % check file size
    file_list(ii).data_size = file_list(ii).bytes - 40;
    
    path = [SEV_DIR file_list(ii).name];
    fid = fopen(path, 'rb');
    if fid < 0
        warning([path ' not opened'])
        return
    end
    
    % create and fill streamHeader struct
    streamHeader = [];
    
    streamHeader.fileSizeBytes   = fread(fid,1,'uint64');
    streamHeader.fileType        = char(fread(fid,3,'char')');
    streamHeader.fileVersion     = fread(fid,1,'char');
    
    % event name of stream
    s = regexp(name, '_', 'split');
    ind = cellfun(@isempty,s); s = s(~ind); % remove any empty cells, like if name is 'Raw_'
    if length(s) > 1
        nm = strcat(s{end-1}, '____'); nm = nm(1:4);
        streamHeader.eventName = nm;
    else
        streamHeader.eventName = name;
    end
    
    if streamHeader.fileVersion < 4
        
        % prior to v3, OpenEx and RS4 were not setting this properly 
        % (one of them was flipping it)
        if streamHeader.fileVersion == 3
            streamHeader.eventName  = char(fread(fid,4,'char')');
        else
            oldEventName  = char(fread(fid,4,'char')');
            
            % if name from file is way off, then don't use it.
            flippedName = fliplr(oldEventName);
            if strcmp(streamHeader.eventName, oldEventName) == 1 || ...
                    strcmp(streamHeader.eventName, flippedName) == 1
            else
                streamHeader.eventName  = oldEventName;
            end
            %streamHeader.eventName  = fliplr(char(fread(fid,4,'char')'));
        end
        %else
        %    streamHeader.eventName  = fliplr(char(fread(fid,4,'char')'));
        %end
        
        % current channel of stream
        streamHeader.channelNum        = fread(fid, 1, 'uint16');
        file_list(ii).chan = streamHeader.channelNum;
        % total number of channels in the stream
        streamHeader.totalNumChannels  = fread(fid, 1, 'uint16');
        % number of bytes per sample
        streamHeader.sampleWidthBytes  = fread(fid, 1, 'uint16');
        reserved                 = fread(fid, 1, 'uint16');
        
        % data format of stream in lower four bits
        dform = fread(fid, 1, 'uint8');
        streamHeader.dForm      = ALLOWED_FORMATS{bitand(dform,7)+1};
        
        % used to compute actual sampling rate
        streamHeader.decimate   = fread(fid, 1, 'uint8');
        streamHeader.rate       = fread(fid, 1, 'uint16');
    else
        error([file_list(ii).name ' has unknown version ' num2str(streamHeader.fileVersion)]);
    end
    
    % compute sampling rate
    if streamHeader.fileVersion > 0
        %streamHeader.fs = 2^(streamHeader.rate)*25000000/2^12/streamHeader.decimate;
        streamHeader.fs = 2^(streamHeader.rate - 12) * 25000000 / streamHeader.decimate;

    else
        % make some assumptions if we don't have a real header
        streamHeader.dForm = 'single';
        streamHeader.fs = 24414.0625;
        s = regexp(file_list(ii).name, '_', 'split');
        streamHeader.eventName = s{end-1};
        streamHeader.channelNum = str2double(regexp(s{end},  '\d+', 'match'));
        file_list(ii).chan = streamHeader.channelNum;
        warning('%s has empty header; assuming %s ch %d format %s\nupgrade to OpenEx v2.18 or above\n', ...
            file_list(ii).name, streamHeader.eventName, ...
            streamHeader.channelNum, streamHeader.dForm);
    end
    
    if FS > 0
        streamHeader.fs = FS;
    end
    
    % add log info if it exists
    if JUSTNAMES == 0
        file_list(ii).start_sample = 1;
        file_list(ii).gaps = [];
        file_list(ii).gap_text = '';
        for jj = 1:length(sample_info)
            if strcmp(streamHeader.eventName, sample_info(jj).name)
                if file_list(ii).hour == sample_info(jj).hour
                    file_list(ii).start_sample = sample_info(jj).start_sample;
                    file_list(ii).gaps = sample_info(jj).gaps;
                    file_list(ii).gap_text = sample_info(jj).gap_text;
                end
            end
        end
    end
    
    % check variable name (workaround for makeValidName support in older Matlab)
    % varname = matlab.lang.makeValidName(streamHeader.eventName); % newer matlab supports this instead
    varname = streamHeader.eventName;
    prepend_x = 0;
    for jj = 1:numel(varname)
        % replace bad field characters with '_'
        if ~isletter(varname(jj)) && isnan(str2double(varname(jj)))
            varname(jj) = '_';
        end
        
        % can't start field name with an underscore or number
        if jj == 1 && (varname(jj) == '_' || ~isnan(str2double(varname(jj))))
            prepend_x = 1;
        end
    end
    
    if prepend_x
        varname = ['x' varname];
    end
    
    %fprintf('%s   %s\n', varname, matlab.lang.makeValidName(streamHeader.eventName))
    
    if ~isvarname(streamHeader.eventName)
        warning('%s is not a valid Matlab variable name, changing to %s', streamHeader.eventName, varname);
    end
    
    func = str2func(streamHeader.dForm);
    tempvar = func(zeros(1,1));
    w = whos('tempvar');
    file_list(ii).itemSize = w.bytes;
    file_list(ii).npts = file_list(ii).data_size / file_list(ii).itemSize;
    file_list(ii).fs = streamHeader.fs;
    file_list(ii).dForm = streamHeader.dForm;
    file_list(ii).eventName = streamHeader.eventName;
    file_list(ii).varName = varname;
    fclose(fid);
end

eventNames = unique({file_list.eventName});
if JUSTNAMES
    data = eventNames;
    return
end

if T2 > 0
    validTimeRange = [T1; T2];
else
    validTimeRange = [T1; Inf];
end

if ~isempty(RANGES)
    validTimeRange = RANGES;
end
numRanges = size(validTimeRange, 2);

if numRanges > 0
    data.time_ranges = validTimeRange;
end

for ev = 1:numel(eventNames)
    
    thisEvent = eventNames{ev};
    
    if ~strcmp(EVENTNAME, '') && ~strcmp(EVENTNAME, thisEvent)
        continue
    end
    
    file_list_temp = [];
    for j = 1:length(file_list)
        if strcmp(file_list(j).eventName, thisEvent)
            file_list_temp = [file_list_temp file_list(j)];
        end
    end
    
    fs = file_list_temp(1).fs;
    eventName = file_list_temp(1).eventName;
    dForm = file_list_temp(1).dForm;
    
    chan_arr = [file_list_temp.chan];
    hour_arr = [file_list_temp.hour];
    max_chan = max(chan_arr);
    min_chan = min(chan_arr);
    max_hour = max(hour_arr);
    hour_values = sort(unique(hour_arr));
    
    % preallocate data array
    if ~any(CHANNEL == 0)
        matching_ch = find(chan_arr == min(CHANNEL));
        if ~all(ismember(CHANNEL, chan_arr))
            error('Channel(s) %s not found in store %s', num2str(CHANNEL(~ismember(CHANNEL, chan_arr))), eventName);
            continue
        end
    elseif singleFile
        matching_ch = 1;
    else
        matching_ch = find(chan_arr == min_chan);
    end
    
    % determine total samples if there is chunking
    % and how many samples are in each file
    total_samples = 0;
    total_samples_exp = 0; % expected, if gaps are accounted for
    
    npts = zeros(1, numel(hour_values)); % number actually in the file, if gaps
    nexp = zeros(1, numel(hour_values)); % number we expected without gaps
    for jjj = hour_values
        temp_num = intersect(find(hour_arr == jjj), matching_ch);
        
        % actual samples
        npts(jjj+1) = file_list_temp(temp_num).npts;
        total_samples = total_samples + npts(jjj+1);
        
        % expected samples
        total_samples_exp = file_list_temp(temp_num).start_sample;
        ggg = file_list_temp(temp_num).gaps;
        if size(ggg, 1) == 2
            ggg(2,:) = ggg(2,:) - 1;
            missing = sum(diff(ggg));
        else
            missing = 0;
        end
        nexp(jjj+1) = npts(jjj+1) + missing;
        total_samples_exp = total_samples_exp + nexp(jjj+1);
    end
    
    % if we are doing time filtering, determine which files we need to read
    % from and how many samples
    absoluteStartSample = zeros(1, numRanges);
    absoluteEndSample = zeros(1, numRanges);
    
    startHourFile = zeros(1, numRanges);
    endHourFile = zeros(1, numRanges);
    
    startHourSamplesToSkip = zeros(1, numRanges);
    endHourSamplesEnd = zeros(1, numRanges);
    
    for jj = 1:numRanges
        
        % find recording start sample
        this_start_sample = file_list_temp(temp_num).start_sample;
        minSample = time2sample(validTimeRange(1,jj), 'FS', fs, 'T1', 1);
        absoluteStartSample(jj) = max(minSample, 0) + 1;
        maxSample = time2sample(validTimeRange(2,jj), 'FS', fs, 'T2', 1);
        absoluteEndSample(jj) = min(max(maxSample, 0) + 1, total_samples);
        
        curr_samples = 0;
        for kk = hour_values
            if curr_samples <= absoluteStartSample(jj)
                startHourSamplesToSkip(jj) = absoluteStartSample(jj) - curr_samples - 1;
                startHourFile(jj) = kk;
            end
            if curr_samples + npts(kk+1) >= absoluteEndSample(jj)
                endHourSamplesEnd(jj) = absoluteEndSample(jj) - curr_samples;
                endHourFile(jj) = kk;
                break
            end
            curr_samples = curr_samples + npts(kk+1);
        end
    end    
    
    % now allocate it
    if ~any(CHANNEL == 0)
        % read selected
        channels = sort(unique(CHANNEL));
    else
        % read all
        channels = sort(unique(chan_arr));
    end
        
    data.(eventName).channels = channels;
    
    if ~all(cellfun(@isempty, {file_list_temp.gap_text})) && length(hour_values) > 1
        warning('can not read split files when there are gaps');
        data.(eventName).data = [];
        data.(eventName).name = eventName;
        data.(eventName).fs = fs;
        return
    else
        data.(eventName).data = cell(1, numRanges);
        for jj = 1:numRanges
            data.(eventName).data{jj} = zeros(numel(channels), absoluteEndSample(jj) - absoluteStartSample(jj) + 1 + this_start_sample, dForm);
        end
    end
    
    % loop through the time ranges
    for ii = 1:numRanges
        
        bigIndex = 1;
        % loop through the channels
        for chan = channels
            chanIndex = this_start_sample;
            matching_ch = find(chan_arr == chan);
            
            % loop through the chunks
            for kk = startHourFile(ii):endHourFile(ii)
            
                file_num = intersect(find(hour_arr == kk), matching_ch);
                
                % read rest of file into data array as correct format
                varname = file_list_temp(file_num).varName;
                data.(varname).name = eventName;
                data.(varname).fs = fs;
                
                % open file
                path = [SEV_DIR file_list_temp(file_num).name];
                if kk == startHourFile(ii)
                    firstSample = startHourSamplesToSkip(ii);
                else
                    firstSample = 0;
                end
                if kk == endHourFile(ii)
                    lastSample = endHourSamplesEnd(ii);
                else
                    lastSample = Inf;
                end

                if ~isempty(file_list_temp(file_num).gaps)
                    n = file_list_temp(file_num).npts;
                    ttt = memmapfile(path, 'Format', {'single' [10] 'header'; ...
                                                      dForm [n] 'data'});

                    ggg = file_list_temp(file_num).gaps;
                    data_ind = diff([1 ggg(:)'-file_list_temp(file_num).start_sample])+1;
                    data_ind = cumsum([1 data_ind(1:2:end)]);
                    data_ind(1) = 0;
                    gap_pts = diff(ggg)-1;
                    pieces = cell(1, numel(gap_pts) * 2 + 1);
                    pieces{1} = ttt.data.data(1:ggg(1,1))';
                    % add zero gaps
                    for mm = 1:length(gap_pts)
                        pieces{mm*2} = zeros(1, gap_pts(mm));
                    end
                    % add data
                    for mm = 1:length(data_ind)-1
                        pieces{mm*2-1} = ttt.data.data(data_ind(mm)+1:data_ind(mm+1))';
                    end
                    % concatenate into one array
                    pieces{mm*2+1} = ttt.data.data(data_ind(end):end)';
                    ddd = cat(2, pieces{:});
                    ddd = ddd(firstSample+1:lastSample);
                else
                    fid = fopen(path, 'rb');
                    if fid < 0
                        warning([path ' not opened'])
                        return
                    end
                            
                    % skip first 40 bytes from header
                    fseek(fid, 40, 'bof');
                    
                    % skip ahead
                    fseek(fid, firstSample*file_list_temp(file_num).itemSize, 'cof');
                    ddd = fread(fid, lastSample - firstSample, ['*' dForm])';
                    
                    % close file
                    fclose(fid);
                end
                readSize = numel(ddd);
                data.(varname).data{ii}(bigIndex, chanIndex:chanIndex + readSize - 1) = ddd;
                
                chanIndex = chanIndex + readSize;
                bigIndex = bigIndex + 1;
                
                %if VERBOSE
                %    file_list(file_num)
                %end
            end
            data.(varname).data{ii} = data.(varname).data{ii}(:,1:chanIndex-1);
        end
    end
    if numRanges == 1
        data.(varname).data = [data.(varname).data{ii}];
    end
end
