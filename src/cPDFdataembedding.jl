module cPDFdataembedding

__init__() = _check_cpdf()

using XML, JLD2

export 
    meta_add_raw_data, meta_add_raw_data!, 
    meta_extract_raw_data, 
    
    attach_file, attach_file!, 
    extract_attachments,

    attach_jld2, attach_jld2!,
    extract_jld2s,

    attach_script, attach_script!,
    extract_scripts


function _check_cpdf()
    cmd = Sys.which("cpdf")
    if cmd == nothing
        error("Coherent PDF command line tool (cpdf) not found. Please install it from https://www.coherentpdf.com/ and ensure it is in your PATH.")
    end
end

tmpdir = ""

function _mktempdir()
    global tmpdir
    if tmpdir == ""
        tmpdir = mktempdir()
    end
end

function _rmtempdir()
    global tmpdir
    if tmpdir != ""
        #rm(tmpdir, recursive=true)
        tmpdir = ""
    end
end

function _extract_meta_from_pdf(pdf_path::String)
    tmpdir = _mktempdir()
    xml_path = joinpath(tmpdir, "extracted.xml")
    
    cmd = `cpdf -print-metadata $pdf_path`
    metadata = read(cmd)

    if isempty(metadata)
        # create metadata
        tmp_pdf = joinpath(tmpdir, "tmp.pdf")
        cmd = `cpdf -create-metadata $pdf_path -o $tmp_pdf`
        run(cmd)
        cmd = `cpdf -print-metadata $tmp_pdf`
        metadata = run(cmd)
        rm(tmp_pdf)
        # write the metadata to an XML file
        open(xml_path, "w") do f
            write(f, metadata)
        end
        if !isfile(xml_path) || filesize(xml_path) == 0
            error("Failed to create metadata XML from PDF: $pdf_path")
        end
    else
        # write the metadata to an XML file
        open(xml_path, "w") do f
            write(f, metadata)
        end
        if !isfile(xml_path) || filesize(xml_path) == 0
            error("Failed to extract metadata XML from PDF: $pdf_path")
        end
    end
    
    return xml_path
end

function _add_data_to_meta(data::String)
    _mktempdir()
    xml_path = joinpath(tmpdir, "extracted.xml")
    
    if !isfile(xml_path)
        error("No metadata XML file found. Please extract metadata first.")
    end
    
    doc = read(xml_path, Node)

    # search for the <x:xmpmeta> element
    #xmpmeta = findfirst(Iterators.filter(x -> tag(x) == "x:xmpmeta", doc))
    xmpmeta_idx = findfirst(x -> tag(x) == "x:xmpmeta", children(doc))
    if xmpmeta_idx == nothing
        error("No <x:xmpmeta> element found in the XML.")
    end
    xmpmeta = doc[xmpmeta_idx]

    data_node = XML.Element("x:rawdata", data)

    # check if <x:xmpmeta> has a <x:cPDFdataembedding> child
    if findfirst(x-> tag(x) == "x:cPDFdataembedding", children(xmpmeta)) == nothing
        # create <x:cPDFdataembedding> if it doesn't exist
        dataparent = XML.Element("x:cPDFdataembedding")
        push!(xmpmeta, dataparent)
    end
    dataparent_idx = findfirst(x -> tag(x) == "x:cPDFdataembedding", children(xmpmeta))
    if dataparent_idx == nothing
        error("No <x:cPDFdataembedding> element found/not created in the XML.")
    end
    dataparent = xmpmeta[dataparent_idx]
    # add the data node to the <x:cPDFdataembedding> element
    push!(dataparent, data_node)
    # write the modified XML back to the file
    XML.write(xml_path, doc)
    return xml_path
end

function _embed(pdf_path::String, data::String, out_path::String)
    _mktempdir()
    xml_path = _extract_meta_from_pdf(pdf_path)
    xml_path = _add_data_to_meta(data)
    tmp_pdf = joinpath(tmpdir, "tmp.pdf")
    cmd = `cpdf -set-metadata $xml_path $pdf_path -o $tmp_pdf`
    run(cmd)
    if !isfile(tmp_pdf)
        error("Failed to embed data into PDF: $pdf_path")
    end
    if out_path != tmp_pdf
        cmd = `cp $tmp_pdf $out_path`
        run(cmd)
    end
    if !isfile(out_path)
        error("Failed to embed data into PDF: $pdf_path")
    end
    return out_path
end

function meta_add_raw_data(pdf_path::String, data::String, out_path::String="")
    _mktempdir()
    if out_path == ""
        out_path = joinpath(tmpdir, "tmp.pdf")
    end
    if out_path == pdf_path
        error("Use meta_add_raw_data() to overwrite the original PDF.")
    end
    out_path = _embed(pdf_path, data, out_path)
    _rmtempdir() # only the ref, not the actual temp dir
    return out_path
end

function meta_add_raw_data!(pdf_path::String, data::String)
    # overwrite the original PDF
    out_path = pdf_path
    _mktempdir()
    out_path = _embed(pdf_path, data, out_path)
    _rmtempdir() # only the ref, not the actual temp dir
    return out_path
end

# Function to extract embedded data from a PDF
function meta_extract_raw_data(pdf_path::String)
    _mktempdir()
    xml_path = _extract_meta_from_pdf(pdf_path)
    doc = read(xml_path, Node)

    # search for the <x:xmpmeta> element
    xmpmeta_idx = findfirst(x -> tag(x) == "x:xmpmeta", children(doc))
    if xmpmeta_idx == nothing
        error("No <x:xmpmeta> element found in the XML.")
    end
    xmpmeta = doc[xmpmeta_idx]

    # search for the <x:cPDFdataembedding> element
    dataparent_idx = findfirst(x -> tag(x) == "x:cPDFdataembedding", children(xmpmeta))
    if dataparent_idx == nothing
        return ""  # No data embedded
    end
    dataparent = xmpmeta[dataparent_idx]

    # extract all <x:rawdata> elements
    data_nodes = filter(x -> tag(x) == "x:rawdata", children(dataparent))
    
    if isempty(data_nodes)
        return ""  # No data embedded
    end

    # return data as array of strings
    data = String[]
    for node in data_nodes
        push!(data, simple_value(node))
    end
    _rmtempdir() # only the ref, not the actual temp dir
    return data
end


function attach_file(pdf_path::String, file_path::String, out_path::String="")
    _mktempdir()
    if out_path == ""
        out_path = joinpath(tmpdir, "tmp.pdf")
    end
    if out_path == pdf_path
        error("Use attach_file!() to overwrite the original PDF.")
    end
    
    cmd = `cpdf -attach-file $file_path $pdf_path -o $out_path`
    run(cmd)
    
    if !isfile(out_path)
        error("Failed to attach file to PDF: $pdf_path")
    end
    
    _rmtempdir() # only the ref, not the actual temp dir
    return out_path
end

function attach_file!(pdf_path::String, file_path::String)
    # overwrite the original PDF
    _mktempdir()
    tmp_pdf = attach_file(pdf_path, file_path)
    out_path = pdf_path
    cmd = `cp $tmp_pdf $out_path`
    run(cmd)
    
    if !isfile(out_path)
        error("Failed to attach file to PDF: $pdf_path")
    end
    
    _rmtempdir() # only the ref, not the actual temp dir
    return out_path
end


function extract_attachments(pdf_path::String, out_dir::String="")
    _mktempdir()
    if out_dir == ""
        out_dir = tmpdir
    elseif !isdir(out_dir)
        mkdir(out_dir)
    end
    
    cmd = `cpdf -list-attached-files $pdf_path` # format <id> <file_name>\n
    attachments = read(cmd, String)

    
    if isempty(attachments)
        return []  # No attachments found
    end
    
    # Parse the attachments
    attachment_list = split(attachments, "\n")
    attachment_list = filter(x -> !isempty(x), attachment_list)  # remove empty lines
    # remove id
    attachment_list = map(x -> split(x, " ", limit=2)[2], attachment_list)
    extracted_files = String[]

    cmd = `cpdf -dump-attachments $pdf_path -o $out_dir`
    run(cmd)

    for file_name in attachment_list
        file_path = joinpath(out_dir, file_name)
        if isfile(file_path)
            push!(extracted_files, file_path)
        else
            warn("Attachment $file_name not found in the output directory: $out_dir")
        end
    end
    
    _rmtempdir() # only the ref, not the actual temp dir
    return extracted_files
end

function attach_jld2(pdf_path::String, data, dataname::String="data", out_path::String="")
    _mktempdir()
    if out_path == ""
        out_path = joinpath(tmpdir, "tmp.pdf")
    end
    if out_path == pdf_path
        error("Use attach_jld2!() to overwrite the original PDF.")
    end
    
    # Save data to a temporary JLD2 file
    jld2_path = joinpath(tmpdir, "$dataname.jld2")
    JLD2.@save jld2_path data

    # Attach the JLD2 file to the PDF
    out_path = attach_file(pdf_path, jld2_path, out_path)
    
    _rmtempdir() # only the ref, not the actual temp dir
    return out_path
end

function attach_jld2!(pdf_path::String, data, dataname::String="data")
    # overwrite the original PDF
    _mktempdir()
    jld2_path = joinpath(tmpdir, "$dataname.jld2")
    JLD2.@save jld2_path data

    out_path = pdf_path
    out_path = attach_file!(pdf_path, jld2_path)
    
    _rmtempdir() # only the ref, not the actual temp dir
    return out_path
end

function extract_jld2s(pdf_path::String, out_dir::String="")
    _mktempdir()
    if out_dir == ""
        out_dir = tmpdir
    elseif !isdir(out_dir)
        mkdir(out_dir)
    end
    
    # Extract attachments
    extracted_files = extract_attachments(pdf_path, tmpdir)
    
    jld2_files = filter(x -> endswith(x, ".jld2"), extracted_files)
    
    if isempty(jld2_files)
        return []  # No JLD2 files found
    end

    # move jld2 files to out_dir
    if out_dir != tmpdir
        for (i, jld2_file) in enumerate(jld2_files)
            new_path = joinpath(out_dir, basename(jld2_file))
            mv(jld2_file, new_path)
            jld2_files[i] = new_path  # update the path in the list
        end
        return jld2_files
    end
    
    data = Dict{String, Any}()
    for jld2_file in jld2_files
        dataname = basename(jld2_file)
        dataname = chop(dataname, tail=5) # remove .jld2 extension
        data[dataname] = JLD2.load(jld2_file)
    end
    _rmtempdir() # only the ref, not the actual temp dir
    return data
end

function attach_script(pdf_path::String, script::String, scriptname::String="script.jl", out_path::String="")
    _mktempdir()
    if out_path == ""
        out_path = joinpath(tmpdir, "tmp.pdf")
    end
    if out_path == pdf_path
        error("Use attach_script!() to overwrite the original PDF.")
    end
    
    # Save script to a temporary file
    script_path = joinpath(tmpdir, scriptname)
    open(script_path, "w") do f
        write(f, script)
    end

    # Attach the script file to the PDF
    out_path = attach_file(pdf_path, script_path, out_path)
    
    _rmtempdir() # only the ref, not the actual temp dir
    return out_path
end

function attach_script!(pdf_path::String, script::String, scriptname::String="script.jl")
    # overwrite the original PDF
    _mktempdir()
    script_path = joinpath(tmpdir, scriptname)
    open(script_path, "w") do f
        write(f, script)
    end

    out_path = pdf_path
    out_path = attach_file!(pdf_path, script_path)
    
    _rmtempdir() # only the ref, not the actual temp dir
    return out_path
end

function extract_scripts(pdf_path::String, out_dir::String="")
    _mktempdir()
    if out_dir == ""
        out_dir = tmpdir
    elseif !isdir(out_dir)
        mkdir(out_dir)
    end
    
    # Extract attachments
    extracted_files = extract_attachments(pdf_path, tmpdir)
    
    script_files = filter(x -> endswith(x, ".jl"), extracted_files)
    
    if isempty(script_files)
        return []  # No script files found
    end

    # move script files to out_dir
    if out_dir != tmpdir
        for (i, script_file) in enumerate(script_files)
            new_path = joinpath(out_dir, basename(script_file))
            mv(script_file, new_path)
            script_files[i] = new_path  # update the path in the list
        end
        return script_files
    end
    
    scripts = Dict{String, String}()
    for script_file in script_files
        scripts[basename(script_file)] = read(script_file, String)
    end
    _rmtempdir() # only the ref, not the actual temp dir
    return scripts
end





end # module cPDFdataembedding
