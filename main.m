%% main.m
% Toolbox-free Face Detection + PCA (Eigenfaces) Recognition + Attendance
% Works without Image Processing Toolbox or Computer Vision Toolbox.
% Save as main.m and run `main`.

function main
    clc; clear; close all;

    % Create required folders
    if ~exist('database','dir'), mkdir('database'); end
    if ~exist('logs','dir'), mkdir('logs'); end
    if ~exist('model','dir'), mkdir('model'); end

    % GUI
    fig = uifigure('Name','Face Recognition (Toolbox-free)','Position',[300 120 900 640]);
    ax  = uiaxes(fig,'Position',[30 150 600 440]);
    title(ax,'Camera / Preview'); axis(ax,'off');

    % name label displayed BELOW the preview (Option B)
    nameLabel = uilabel(fig, ...
        'Text','Recognized: ---', ...
        'Position',[30 120 600 24], ...
        'HorizontalAlignment','center', ...
        'FontSize',16, ...
        'FontWeight','bold');

    lbl = uilabel(fig,'Text','System Idle','Position',[30 80 840 30],'HorizontalAlignment','center','FontSize',14);

    uibutton(fig,'Text','Start Camera','Position',[660 470 200 40], 'ButtonPushedFcn',@(s,e)startCamera(s));
    uibutton(fig,'Text','Stop Camera','Position',[660 420 200 40],  'ButtonPushedFcn',@(s,e)stopCamera(s));
    uibutton(fig,'Text','Add New Person','Position',[660 370 200 40],'ButtonPushedFcn',@(s,e)addNewPerson(s));
    uibutton(fig,'Text','Train Database','Position',[660 320 200 40],'ButtonPushedFcn',@(s,e)trainDatabase(s));
    uibutton(fig,'Text','Start Recognition','Position',[660 270 200 40],'ButtonPushedFcn',@(s,e)startRecognition(s));
    uibutton(fig,'Text','Stop Recognition','Position',[660 220 200 40],'ButtonPushedFcn',@(s,e)stopRecognition(s));
    uibutton(fig,'Text','Export Attendance CSV','Position',[660 170 200 40],'ButtonPushedFcn',@(s,e)exportAttendance(s));

    % store appdata
    setappdata(fig,'ax',ax);
    setappdata(fig,'lbl',lbl);
    setappdata(fig,'cam',[]);
    setappdata(fig,'running',false);
    setappdata(fig,'recognizing',false);
    setappdata(fig,'nameLabel',nameLabel);

    % show helper instructions
    lbl2 = uilabel(fig,'Text',["Notes: 1) This version is toolbox-free.","2) If webcam isn't available you'll be asked for a video or images."],...
        'Position',[30 40 840 30],'HorizontalAlignment','left','FontSize',11);
end

%% ----------------------- Camera controls ------------------------------
function startCamera(src)
    fig = ancestor(src,'figure');
    lbl = getappdata(fig,'lbl'); ax = getappdata(fig,'ax');

    try
        cam = webcam;                      % try webcam
        setappdata(fig,'cam',cam);
        setappdata(fig,'running',true);
        lbl.Text = 'Camera started.';
        img = snapshot(cam);
        showImage(ax, img);
    catch
        % webcam not available: ask user to choose a video file or directory of images
        choice = questdlg(['No webcam detected. Would you like to: ' ...
                           '\n(1) Select a video file to use OR (2) Select a folder of images?'], ...
                           'No Webcam', 'Select Video','Select Folder','Cancel','Select Folder');
        if strcmp(choice,'Select Video')
            [file,path] = uigetfile({'*.mp4;*.avi;*.mov','Video Files (*.mp4,*.avi,*.mov)';'*.*','All Files'},'Select Video');
            if isequal(file,0), lbl.Text = 'Camera start cancelled.'; return; end
            vidpath = fullfile(path,file);
            vid = VideoReader(vidpath);
            setappdata(fig,'cam',vid);       % store VideoReader as 'cam'
            setappdata(fig,'running',true);
            lbl.Text = ['Using video file: ',file];
            img = readFrame(vid);
            showImage(ax, img);
        elseif strcmp(choice,'Select Folder')
            folder = uigetdir(pwd,'Select folder containing images');
            if isequal(folder,0), lbl.Text = 'Camera start cancelled.'; return; end
            setappdata(fig,'cam',folder);    % store folder path
            setappdata(fig,'running',true);
            lbl.Text = ['Using images from: ',folder];
            imgfiles = dir(fullfile(folder,'*.*'));
            % find first image
            for k=1:numel(imgfiles)
                [~,~,ext] = fileparts(imgfiles(k).name);
                if ismember(lower(ext),{'.jpg','.jpeg','.png','.bmp'})
                    img = imread(fullfile(folder,imgfiles(k).name));
                    showImage(ax,img); break;
                end
            end
        else
            lbl.Text = 'Camera not started.';
            return;
        end
    end
end

function stopCamera(src)
    fig = ancestor(src,'figure');
    lbl = getappdata(fig,'lbl');
    cam = getappdata(fig,'cam');
    if isempty(cam)
        lbl.Text = 'No camera active.';
        return;
    end
    % clear webcam if present
    try
        if isa(cam,'webcam'), clear cam; end
    catch
        % ignore
    end
    setappdata(fig,'cam',[]);
    setappdata(fig,'running',false);
    lbl.Text = 'Camera stopped.';
    % reset name label
    nameLabel = getappdata(fig,'nameLabel');
    if ~isempty(nameLabel), nameLabel.Text = 'Recognized: ---'; end
end

%% ----------------------- Add New Person (capture) ---------------------
function addNewPerson(src)
    fig = ancestor(src,'figure');
    lbl = getappdata(fig,'lbl'); ax = getappdata(fig,'ax');
    cam = getappdata(fig,'cam');

    if isempty(cam)
        uialert(fig,'Start camera (or load video/images) first.','No Camera');
        return;
    end

    prompt = {'Enter person name (no commas):'};
    dlg = inputdlg(prompt,'New Person', [1 40]);
    if isempty(dlg), return; end
    name = strtrim(dlg{1});
    if isempty(name), uialert(fig,'Name cannot be empty.','Error'); return; end

    folder = fullfile('database',name);
    if ~exist(folder,'dir'), mkdir(folder); end

    lbl.Text = ['Capturing images for: ',name];
    drawnow;

    % capture 10 faces (or less if video/images)
    count = 0; attempts = 0;
    max_attempts = 40;
    while count < 10 && attempts < max_attempts
        attempts = attempts + 1;
        img = grabFrameFromCam(cam);
        if isempty(img), break; end

        bbox = detectFace_toolboxfree(img);    % custom detector (pure MATLAB)

        if isempty(bbox)
            % show current frame and allow manual ROI if user clicks
            showImage(ax,img);
            title(ax,'No face auto-detected. Click and drag to select ROI (or press Cancel).');
            roi = drawROIInteractive(fig,ax);
            if ~isempty(roi)
                bbox = round(roi);
            else
                pause(0.2); continue;
            end
        end

        % Crop and save face
        face = cropAndResize(img, bbox, [150 150]);
        fname = fullfile(folder, sprintf('%s_%02d.jpg', name, count+1));
        imwrite(face, fname);
        count = count + 1;

        % display feedback
        img_disp = insertRectText(img, bbox, sprintf('%s (%d)', name, count));
        showImage(ax, img_disp);
        pause(0.4);
    end

    lbl.Text = sprintf('Captured %d images for %s', count, name);
end

%% ----------------------- Training (PCA / Eigenfaces) -----------------
function trainDatabase(src)
    fig = ancestor(src,'figure');
    lbl = getappdata(fig,'lbl');

    lbl.Text = 'Training: scanning database...'; drawnow;

    persons = dir('database');
    persons = persons([persons.isdir]);
    persons = persons(~ismember({persons.name},{'.','..'}));
    if isempty(persons), uialert(fig,'No persons in database. Add people first.','No Data'); lbl.Text='Idle'; return; end

    X = []; labels = {};
    targetSize = [150 150];
    for i=1:numel(persons)
        pname = persons(i).name;
        imgs = dir(fullfile('database',pname,'*.jpg'));
        for j=1:numel(imgs)
            I = imread(fullfile('database',pname,imgs(j).name));
            face = rgb2gray_simple(I);            % custom grayscale
            face = imresize_simple(face, targetSize); % custom resize
            vec = double(face(:))';                % 1 x N
            X = [X; vec];                          %#ok<AGROW>
            labels{end+1} = pname;                 %#ok<AGROW>
        end
    end

    if isempty(X), uialert(fig,'No face images found.','Error'); lbl.Text='Idle'; return; end

    lbl.Text = 'Computing PCA (Eigenfaces)...'; drawnow;
    % center data
    mu = mean(X,1);
    Xc = double(X) - mu;

    % compute SVD on centered data (economical)
    [U,S,V] = svd(Xc','econ');   % columns of U are eigenvectors of covariance
    eigvecs = U;                 % each column is an eigenface (size: Npix x num_eigs)
    eigvals = diag(S).^2;        % energy

    % keep components that explain 95% variance or up to 100 components
    energy = cumsum(eigvals)/sum(eigvals);
    k = find(energy >= 0.95, 1, 'first');
    if isempty(k), k = min(100, size(eigvecs,2)); end
    k = min(k, size(eigvecs,2));
    eigvecs = eigvecs(:,1:k);

    % project training images
    projections = (Xc * eigvecs);

    % save model
    model.mu = mu;
    model.eigvecs = eigvecs;
    model.proj = projections;
    model.labels = labels;
    save(fullfile('model','face_model.mat'),'model');

    lbl.Text = sprintf('Training done. Kept %d components.',k);
end

%% ----------------------- Recognition loop ---------------------------
function startRecognition(src)
    fig = ancestor(src,'figure');
    lbl = getappdata(fig,'lbl'); ax = getappdata(fig,'ax'); nameLabel = getappdata(fig,'nameLabel');
    cam = getappdata(fig,'cam');

    if isempty(cam)
        uialert(fig,'Start camera (or load video/images) first.','No Camera');
        return;
    end
    if ~isfile(fullfile('model','face_model.mat'))
        uialert(fig,'Train the database first.','No Model');
        return;
    end

    data = load(fullfile('model','face_model.mat')); model = data.model;

    setappdata(fig,'recognizing',true);
    lbl.Text = 'Recognition started.';

    while getappdata(fig,'recognizing')
        img = grabFrameFromCam(cam);
        if isempty(img), break; end

        bbox = detectFace_toolboxfree(img);
        if isempty(bbox)
            showImage(ax,img);
            % reset name label when no face
            nameLabel.Text = 'Recognized: ---';
            drawnow;
            pause(0.05);
            continue;
        end

        face = cropAndResize(img, bbox, [150 150]);
        faceg = double(rgb2gray_simple(face));
        vec = faceg(:)' - model.mu;
        proj = vec * model.eigvecs;
        % nearest neighbor
        dists = vecnorm(model.proj - proj, 2, 2);
        [mind, idx] = min(dists);

        % threshold for unknown (set relative)
        thresh = median(dists) * 0.6 + 50; %#ok<NASGU> % heuristic
        if mind < thresh
            name = model.labels{idx};
        else
            name = 'Unknown';
        end

        % annotate (rectangle only) and show
        img_disp = insertRectangleOnly(img, bbox);
        showImage(ax, img_disp);

        % update name label below preview (Option B)
        nameLabel.Text = ['Recognized: ', name];

        % log attendance for recognized names
        if ~strcmp(name,'Unknown')
            logAttendance(name);
        end

        drawnow;
        pause(0.08);
    end

    lbl.Text = 'Recognition stopped.';
end

function stopRecognition(src)
    fig = ancestor(src,'figure');
    setappdata(fig,'recognizing',false);
    lbl = getappdata(fig,'lbl'); lbl.Text = 'Recognition stopping...';
end

%% ----------------------- Utilities & helpers -------------------------

% Grab a single frame from stored 'cam' object (webcam, VideoReader, or folder)
function img = grabFrameFromCam(cam)
    img = [];
    if isempty(cam), return; end
    try
        if isa(cam,'webcam')
            img = snapshot(cam);
        elseif isa(cam,'VideoReader')
            if hasFrame(cam)
                img = readFrame(cam);
            else
                img = [];
            end
        elseif ischar(cam) || isstring(cam)
            % folder of images: rotate through files (store index)
            folder = char(cam);
            idxKey = 'folderIndex';
            idx = getappdata(0, idxKey);
            if isempty(idx), idx = 1; end
            files = dir(fullfile(folder,'*.*'));
            % filter image files
            isimg = false(size(files));
            for i=1:numel(files)
                [~,~,ext] = fileparts(files(i).name);
                isimg(i) = ismember(lower(ext),{'.jpg','.jpeg','.png','.bmp'});
            end
            files = files(isimg);
            if isempty(files), img = []; return; end
            if idx > numel(files), idx = 1; end
            img = imread(fullfile(folder,files(idx).name));
            idx = idx + 1;
            setappdata(0, idxKey, idx);
        else
            % unknown type
            img = [];
        end
    catch
        img = [];
    end
end

% Show color image on uiaxes without requiring imshow
function showImage(ax, img)
    try %#ok<TRYNC>
        if ~isempty(img)
            % convert to uint8 if double
            if ~isa(img,'uint8')
                img = uint8(img);
            end
            cla(ax);
            % use image() to avoid dependency on imshow
            ih = image(ax, img);
            axis(ax,'image','off');
            set(ahandle(ax),'YDir','normal'); % ensure correct orientation
            drawnow;
        end
    end
end

% helper to get underlying axes handle (works for uiaxes too)
function h = ahandle(uiax)
    try
        h = get(uiax,'Children'); % fallback
    catch
        h = uiax;
    end
end

% Manual ROI draw: user drags rectangle; returns bbox [x y w h] or []
function bbox = drawROIInteractive(fig,ax)
    bbox = [];
    try
        w = uiprogressdlg(fig,'Title','Select ROI','Message','Draw rectangle on image then press OK or Cancel','Cancelable','on');
        % Use built-in drawrectangle if available
        try
            h = drawrectangle(ax);
            uiwait(msgbox('Adjust rectangle then press OK to accept, or Cancel to skip.','ROI','modal'));
            pos = h.Position;
            delete(h);
            close(w);
            bbox = pos;
        catch
            % fallback: ask user to click two corners
            uiwait(msgbox('Click two corners on the axes: top-left then bottom-right','ROI','modal'));
            [x1,y1] = ginput(1); % may not work for uiaxes
            [x2,y2] = ginput(1);
            x = min(x1,x2); y = min(y1,y2);
            bbox = [x y abs(x2-x1) abs(y2-y1)];
            close(w);
        end
    catch
        bbox = [];
    end
end

% crop and resize to target size (nearest neighbor)
function face = cropAndResize(img, bbox, targetSize)
    % bbox may have fractional values
    bbox = round(bbox);
    x = max(1, bbox(1)); y = max(1, bbox(2));
    w = max(1, bbox(3)); h = max(1, bbox(4));
    [H,W,~] = size(img);
    x2 = min(W, x+w-1); y2 = min(H, y+h-1);
    crop = img(y:y2, x:x2, :);
    face = imresize_simple(crop, targetSize);
end

% Insert rectangle and text onto image (pure-MATLAB) - used for addNewPerson feedback
function imgout = insertRectText(img, bbox, textstr)
    imgout = img;
    bbox = round(bbox);
    x = bbox(1); y = bbox(2); w = bbox(3); h = bbox(4);
    [H,W,~] = size(imgout);
    % draw rectangle by darkening border pixels (thickness 2)
    thickness = max(1, round(min([H,W])*0.003));
    x1 = max(1,x); y1 = max(1,y); x2 = min(W, x+w-1); y2 = min(H, y+h-1);
    for t = 0:thickness-1
        % top & bottom rows
        rtop = y1+t; rbot = y2-t;
        cleft = x1+t; cright = x2-t;
        if rtop>=1 && rtop<=H
            imgout(rtop, max(1,cleft):min(W,cright), :) = uint8(0);
        end
        if rbot>=1 && rbot<=H
            imgout(rbot, max(1,cleft):min(W,cright), :) = uint8(0);
        end
        % left & right cols
        if cleft>=1 && cleft<=W
            imgout(max(1,rtop):min(H,rbot), cleft, :) = uint8(0);
        end
        if cright>=1 && cright<=W
            imgout(max(1,rtop):min(H,rbot), cright, :) = uint8(0);
        end
    end
    % overlay text at top-left of bbox (simple)
    if ~isempty(textstr)
        posY = max(1, y1 - 18);
        posX = x1;
        imgout = drawTextSimple(imgout, posX, posY, textstr);
    end
end

% Draw rectangle only (no text) for recognition display
function imgout = insertRectangleOnly(img, bbox)
    imgout = img;
    bbox = round(bbox);
    x = bbox(1); y = bbox(2); w = bbox(3); h = bbox(4);
    [H,W,~] = size(imgout);
    thickness = max(1, round(min([H,W])*0.003));
    x1 = max(1,x); y1 = max(1,y); x2 = min(W, x+w-1); y2 = min(H, y+h-1);
    for t = 0:thickness-1
        rtop = y1+t; rbot = y2-t;
        cleft = x1+t; cright = x2-t;
        if rtop>=1 && rtop<=H
            imgout(rtop, max(1,cleft):min(W,cright), :) = uint8(0);
        end
        if rbot>=1 && rbot<=H
            imgout(rbot, max(1,cleft):min(W,cright), :) = uint8(0);
        end
        if cleft>=1 && cleft<=W
            imgout(max(1,rtop):min(H,rbot), cleft, :) = uint8(0);
        end
        if cright>=1 && cright<=W
            imgout(max(1,rtop):min(H,rbot), cright, :) = uint8(0);
        end
    end
end

% Simple text drawing using patching of characters with built-in 'insertText' avoidance:
function img = drawTextSimple(img, x, y, txt)
    % We'll draw text onto a hidden figure and capture it (toolbox-free)
    try
        hfig = figure('Visible','off','Position',[10 10 size(img,2) size(img,1)]);
        ax = axes('Position',[0 0 1 1]);
        imshow(img,'Parent',ax);
        text(ax, x, y, txt, 'FontSize',12, 'FontWeight','bold', 'Color','black', 'BackgroundColor','yellow');
        frame = getframe(hfig);
        img = frame.cdata;
        close(hfig);
    catch
        % fallback: do nothing
    end
end

% Log attendance (append name + timestamp)
function logAttendance(name)
    if isempty(name), return; end
    file = fullfile('logs','attendance_log.csv');
    ts = datestr(now,'yyyy-mm-dd HH:MM:SS');
    if ~isfile(file)
        fid = fopen(file,'w'); fprintf(fid,'Name,Timestamp\n'); fclose(fid);
    end
    fid = fopen(file,'a'); fprintf(fid,'%s,%s\n',name,ts); fclose(fid);
end

% Export attendance CSV (open file explorer at logs)
function exportAttendance(src)
    folder = fullfile(pwd,'logs');
    if ispc
        winopen(folder);
    elseif ismac
        system(['open "',folder,'"']);
    else
        system(['xdg-open "',folder,'" &']);
    end
end

%% ----------------------- Pure-MATLAB Image Helpers --------------------

% simple RGB->gray (no toolbox)
function g = rgb2gray_simple(I)
    if size(I,3) == 1
        g = I;
        return;
    end
    I = double(I);
    g = 0.2989*I(:,:,1) + 0.5870*I(:,:,2) + 0.1140*I(:,:,3);
    g = uint8(g);
end

% nearest-neighbor resize (no toolbox)
function out = imresize_simple(img, targetSize)
    % targetSize = [rows cols] or scalar
    if numel(targetSize) == 1
        outRows = targetSize; outCols = targetSize;
    else
        outRows = targetSize(1); outCols = targetSize(2);
    end
    [inRows, inCols, channels] = size(img);
    if inRows == outRows && inCols == outCols
        out = img;
        return;
    end
    rr = round(linspace(1, inRows, outRows));
    cc = round(linspace(1, inCols, outCols));
    out = zeros(outRows, outCols, channels, 'uint8');
    for ch = 1:channels
        tmp = img(:,:,ch);
        out(:,:,ch) = tmp(rr, cc);
    end
end

% Otsu-like threshold (uses custom histogram)
function T = graythresh_simple(I)
    Iu = uint8(I);
    counts = imhist_simple(Iu);
    p = counts / sum(counts);
    omega = cumsum(p);
    mu = cumsum((0:255)'.*p);
    mu_t = mu(end);
    sigma = (mu_t*omega - mu).^2 ./ (omega .* (1-omega) + eps);
    [~, idx] = max(sigma);
    T = idx-1;
end

function counts = imhist_simple(I)
    counts = zeros(256,1);
    Iu = uint8(I);
    for k = 0:255
        counts(k+1) = sum(Iu(:) == k);
    end
end

% remove small components by area (uses regionprops_simple)
function bw2 = bwareaopen_simple(bw, minarea)
    props = regionprops_simple(bw);
    bw2 = false(size(bw));
    for k = 1:numel(props)
        if props(k).Area >= minarea
            bb = props(k).BoundingBox;
            x = max(1, round(bb(1))); y = max(1, round(bb(2)));
            w = round(bb(3)); h = round(bb(4));
            bw2(y:y+h-1, x:x+w-1) = bw2(y:y+h-1, x:x+w-1) | bw(y:y+h-1, x:x+w-1);
        end
    end
end

% very simple connected component analysis (returns bounding boxes & area)
function props = regionprops_simple(bw)
    bw = logical(bw);
    [H,W] = size(bw);
    visited = false(H,W);
    props = struct('BoundingBox',{},'Area',{});
    label = 0;
    for r=1:H
        for c=1:W
            if bw(r,c) && ~visited(r,c)
                label = label + 1;
                [area,xmin,xmax,ymin,ymax, visited] = bfs_region(bw, visited, r, c);
                props(label).Area = area;
                props(label).BoundingBox = [xmin, ymin, xmax-xmin+1, ymax-ymin+1];
            end
        end
    end
end

function [area, xmin, xmax, ymin, ymax, visited] = bfs_region(bw, visited, r0, c0)
    H = size(bw,1); W = size(bw,2);
    qHead = 1; qTail = 1;
    Q = zeros(H*W,2);
    Q(qTail,:) = [r0 c0]; qTail = qTail + 1;
    visited(r0,c0) = true;
    xmin = c0; xmax = c0; ymin = r0; ymax = r0; area = 0;
    while qHead < qTail
        rc = Q(qHead,:); qHead = qHead + 1;
        r = rc(1); c = rc(2);
        area = area + 1;
        xmin = min(xmin, c); xmax = max(xmax, c);
        ymin = min(ymin, r); ymax = max(ymax, r);
        for dr = -1:1
            for dc = -1:1
                nr = r + dr; nc = c + dc;
                if nr>=1 && nr<=H && nc>=1 && nc<=W && bw(nr,nc) && ~visited(nr,nc)
                    visited(nr,nc) = true;
                    Q(qTail,:) = [nr nc]; qTail = qTail + 1;
                end
            end
        end
    end
end

% Pure-MATLAB detector: grayscale -> blur -> threshold -> largest blob -> bbox
function bbox = detectFace_toolboxfree(img)
    bbox = [];
    if isempty(img), return; end
    % convert to gray
    g = rgb2gray_simple(img);

    % small Gaussian blur (3x3) via conv2
    kernel = [1 2 1; 2 4 2; 1 2 1] / 16;
    gdouble = double(g);
    gblur = conv2(gdouble, kernel, 'same');
    gblur = uint8(gblur);

    % threshold using Otsu-like
    T = graythresh_simple(gblur);
    bw = gblur > T;

    % remove small objects
    bw = bwareaopen_simple(bw, 2000);   % min area heuristic

    % get connected components
    props = regionprops_simple(bw);
    if isempty(props), return; end

    % choose the component with largest area and reasonable aspect ratio
    areas = [props.Area];
    [~, idx] = max(areas);
    bb = props(idx).BoundingBox;
    % expand bounding box a little
    bb(1) = max(1, bb(1) - bb(3)*0.15);
    bb(2) = max(1, bb(2) - bb(4)*0.15);
    bb(3) = min(size(img,2)-bb(1), bb(3) * 1.3);
    bb(4) = min(size(img,1)-bb(2), bb(4) * 1.3);
    bbox = bb;
end
