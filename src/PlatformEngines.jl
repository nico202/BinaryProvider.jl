# In this file, we setup the `gen_download_cmd()`, `gen_unpack_cmd()` and
# `gen_package_cmd()` functions by providing methods to probe the environment
# and determine the most appropriate platform binaries to call.

export gen_download_cmd, gen_unpack_cmd, gen_package_cmd, gen_list_tarball_cmd,
       parse_tarball_listing, gen_sh_cmd, parse_7z_list, parse_tar_list,
       download_verify_unpack, download_verify, unpack

"""
    gen_download_cmd(url::AbstractString, out_path::AbstractString)

Return a `Cmd` that will download resource located at `url` and store it at
the location given by `out_path`.

This method is initialized by `probe_platform_engines()`, which should be
automatically called upon first import of `BinaryProvider`.
"""
gen_download_cmd = (url::AbstractString, out_path::AbstractString) ->
    error("Call `probe_platform_engines()` before `gen_download_cmd()`")

"""
    gen_unpack_cmd(tarball_path::AbstractString, out_path::AbstractString; excludelist::Union{AbstractString, Nothing} = nothing)

Return a `Cmd` that will unpack the given `tarball_path` into the given
`out_path`.  If `out_path` is not already a directory, it will be created.
excludlist is an optional file which contains a list of files that is not unpacked
This option is mainyl used to exclude symlinks from extraction (see: `copyderef`)

This method is initialized by `probe_platform_engines()`, which should be
automatically called upon first import of `BinaryProvider`.
"""
gen_unpack_cmd = (tarball_path::AbstractString, out_path::AbstractString; excludelist::Union{AbstractString, Nothing} = nothing) ->
    error("Call `probe_platform_engines()` before `gen_unpack_cmd()`")

"""
    gen_package_cmd(in_path::AbstractString, tarball_path::AbstractString)

Return a `Cmd` that will package up the given `in_path` directory into a
tarball located at `tarball_path`.

This method is initialized by `probe_platform_engines()`, which should be
automatically called upon first import of `BinaryProvider`.
"""
gen_package_cmd = (in_path::AbstractString, tarball_path::AbstractString) ->
    error("Call `probe_platform_engines()` before `gen_package_cmd()`")

"""
    gen_list_tarball_cmd(tarball_path::AbstractString)

Return a `Cmd` that will list the files contained within the tarball located at
`tarball_path`.  The list will not include directories contained within the
tarball.

This method is initialized by `probe_platform_engines()`, which should be
automatically called upon first import of `BinaryProvider`.
"""
gen_list_tarball_cmd = (tarball_path::AbstractString) ->
    error("Call `probe_platform_engines()` before `gen_list_tarball_cmd()`")

"""
    parse_tarball_listing(output::AbstractString)

Parses the result of `gen_list_tarball_cmd()` into something useful.

This method is initialized by `probe_platform_engines()`, which should be
automatically called upon first import of `BinaryProvider`.
"""
parse_tarball_listing = (output::AbstractString) ->
    error("Call `probe_platform_engines()` before `parse_tarball_listing()`")

"""
    gen_sh_cmd(cmd::Cmd)

Runs a command using `sh`.  On Unices, this will default to the first `sh`
found on the `PATH`, however on Windows if that is not found it will fall back
to the `sh` provided by the `busybox.exe` shipped with Julia.

This method is initialized by `probe_platform_engines()`, which should be
automatically called upon first import of `BinaryProvider`.
"""
gen_sh_cmd = (cmd::Cmd) ->
    error("Call `probe_platform_engines()` before `gen_sh_cmd()`")


"""
    probe_cmd(cmd::Cmd; verbose::Bool = false)

Returns `true` if the given command executes successfully, `false` otherwise.
"""
function probe_cmd(cmd::Cmd; verbose::Bool = false)
    if verbose
        @info("Probing $(cmd.exec[1]) as a possibility...")
    end
    try
        success(cmd)
        if verbose
            @info("  Probe successful for $(cmd.exec[1])")
        end
        return true
    catch
        return false
    end
end

"""
    probe_symlink_creation(dest::AbstractString)

Probes whether we can create a symlink within the given destination directory,
to determine whether a particular filesystem is "symlink-unfriendly".
"""
function probe_symlink_creation(dest::AbstractString)
    while !isdir(dest)
        dest = dirname(dest)
    end

    # Build arbitrary (non-existent) file path name
    link_path = joinpath(dest, "binaryprovider_symlink_test")
    while ispath(link_path)
        link_path *= "1"
    end

    loglevel = Logging.min_enabled_level(current_logger())
    try
        disable_logging(Logging.Warn)
        symlink("foo", link_path)
        return true
    catch e
        if isa(e, Base.IOError)
            return false
        end
        rethrow(e)
    finally
        disable_logging(loglevel-1)
        rm(link_path; force=true)
    end
end

"""
    probe_platform_engines!(;verbose::Bool = false)

Searches the environment for various tools needed to download, unpack, and
package up binaries.  Searches for a download engine to be used by
`gen_download_cmd()` and a compression engine to be used by `gen_unpack_cmd()`,
`gen_package_cmd()`, `gen_list_tarball_cmd()` and `parse_tarball_listing()`, as
well as a `sh` execution engine for `gen_sh_cmd()`.  Running this function
will set the global functions to their appropriate implementations given the
environment this package is running on.

This probing function will automatically search for download engines using a
particular ordering; if you wish to override this ordering and use one over all
others, set the `BINARYPROVIDER_DOWNLOAD_ENGINE` environment variable to its
name, and it will be the only engine searched for. For example, put:

    ENV["BINARYPROVIDER_DOWNLOAD_ENGINE"] = "fetch"

within your `~/.juliarc.jl` file to force `fetch` to be used over `curl`.  If
the given override does not match any of the download engines known to this
function, a warning will be printed and the typical ordering will be performed.

Similarly, if you wish to override the compression engine used, set the
`BINARYPROVIDER_COMPRESSION_ENGINE` environment variable to its name (e.g. `7z`
or `tar`) and it will be the only engine searched for.  If the given override
does not match any of the compression engines known to this function, a warning
will be printed and the typical searching will be performed.

If `verbose` is `true`, print out the various engines as they are searched.
"""
probe_platform_engines!(;verbose::Bool = false) = nothing

"""
    parse_7z_list(output::AbstractString)

Given the output of `7z l`, parse out the listed filenames.  This funciton used
by  `list_tarball_files`.
"""
function parse_7z_list(output::AbstractString)
    lines = [chomp(l) for l in split(output, "\n")]

    # If we didn't get anything, complain immediately
    if isempty(lines)
        return []
    end

    # Remove extraneous "\r" for windows platforms
    for idx in 1:length(lines)
        if endswith(lines[idx], '\r')
            lines[idx] = lines[idx][1:end-1]
        end
    end

    # Find index of " Name".  Have to `collect()` as `findfirst()` doesn't work with
    # generators: https://github.com/JuliaLang/julia/issues/16884
    header_row = findfirst(collect(occursin(" Name", l) && occursin(" Attr", l) for l in lines))
    name_idx = findfirst("Name", lines[header_row])[1]
    attr_idx = findfirst("Attr", lines[header_row])[1] - 1

    # Filter out only the names of files, ignoring directories
    lines = [l[name_idx:end] for l in lines if length(l) > name_idx && l[attr_idx] != 'D']
    if isempty(lines)
        return []
    end

    # Extract within the bounding lines of ------------
    bounds = [i for i in 1:length(lines) if all([c for c in lines[i]] .== Ref('-'))]
    lines = lines[bounds[1]+1:bounds[2]-1]

    # Eliminate `./` prefix, if it exists
    for idx in 1:length(lines)
        if startswith(lines[idx], "./") || startswith(lines[idx], ".\\")
            lines[idx] = lines[idx][3:end]
        end
    end

    return lines
end

"""
    parse_tar_list(output::AbstractString)

Given the output of `tar -t`, parse out the listed filenames.  This funciton
used by `list_tarball_files`.
"""
function parse_tar_list(output::AbstractString)
    lines = [chomp(l) for l in split(output, "\n")]
    for idx in 1:length(lines)
        if endswith(lines[idx], '\r')
            lines[idx] = lines[idx][1:end-1]
        end
    end

    # Drop empty lines and and directories
    lines = [l for l in lines if !isempty(l) && !endswith(l, '/')]

    # Eliminate `./` prefix, if it exists
    for idx in 1:length(lines)
        if startswith(lines[idx], "./") || startswith(lines[idx], ".\\")
            lines[idx] = lines[idx][3:end]
        end
    end

    # make sure paths are always returned in the system's default way
    return Sys.iswindows() ? replace.(lines, ['/' => '\\']) : lines
end

"""
    download(url::AbstractString, dest::AbstractString;
             verbose::Bool = false)

Download file located at `url`, store it at `dest`, continuing if `dest`
already exists and the server and download engine support it.
"""
function download(url::AbstractString, dest::AbstractString;
                  verbose::Bool = false)
    download_cmd = gen_download_cmd(url, dest)
    if verbose
        @info("Downloading $(url) to $(dest)...")
    end
    oc = OutputCollector(download_cmd; verbose=verbose)
    try
        if !wait(oc)
            error()
        end
    catch e
        if isa(e, InterruptException)
            rethrow()
        end
        error("Could not download $(url) to $(dest):\n$(e)")
    end
end

"""
    download_verify(url::AbstractString, hash::AbstractString,
                    dest::AbstractString; verbose::Bool = false,
                    force::Bool = false, quiet_download::Bool = false)

Download file located at `url`, verify it matches the given `hash`, and throw
an error if anything goes wrong.  If `dest` already exists, just verify it. If
`force` is set to `true`, overwrite the given file if it exists but does not
match the given `hash`.

This method returns `true` if the file was downloaded successfully, `false`
if an existing file was removed due to the use of `force`, and throws an error
if `force` is not set and the already-existent file fails verification, or if
`force` is set, verification fails, and then verification fails again after
redownloading the file.

If `quiet_download` is set to `false` (the default), this method will print to
stdout when downloading a new file.  If it is set to `true` (and `verbose` is
set to `false`) the downloading process will be completely silent.  If
`verbose` is set to `true`, messages about integrity verification will be
printed in addition to messages regarding downloading.
"""
function download_verify(url::AbstractString, hash::AbstractString,
                         dest::AbstractString; verbose::Bool = false,
                         force::Bool = false, quiet_download::Bool = false)
    # Whether the file existed in the first place
    file_existed = false

    if isfile(dest)
        file_existed = true
        if verbose
            info_onchange(
                "Destination file $(dest) already exists, verifying...",
                "download_verify_$(dest)",
                @__LINE__,
            )
        end

        # verify download, if it passes, return happy.  If it fails, (and
        # `force` is `true`, re-download!)
        try
            verify(dest, hash; verbose=verbose)
            return true
        catch e
            if isa(e, InterruptException)
                rethrow()
            end
            if !force
                rethrow()
            end
            if verbose
                info_onchange(
                    "Verification failed, re-downloading...",
                    "download_verify_$(dest)",
                    @__LINE__,
                )
            end
        end
    end

    # Make sure the containing folder exists
    mkpath(dirname(dest))

    try
        # Download the file, optionally continuing
        download(url, dest; verbose=verbose || !quiet_download)

        verify(dest, hash; verbose=verbose)
    catch e
        if isa(e, InterruptException)
            rethrow()
        end
        # If the file already existed, it's possible the initially downloaded chunk
        # was bad.  If verification fails after downloading, auto-delete the file
        # and start over from scratch.
        if file_existed
            if verbose
                @info("Continued download didn't work, restarting from scratch")
            end
            rm(dest; force=true)

            # Download and verify from scratch
            download(url, dest; verbose=verbose || !quiet_download)
            verify(dest, hash; verbose=verbose)
        else
            # If it didn't verify properly and we didn't resume, something is
            # very wrong and we must complain mightily.
            rethrow()
        end
    end

    # If the file previously existed, this means we removed it (due to `force`)
    # and redownloaded, so return `false`.  If it didn't exist, then this means
    # that we successfully downloaded it, so return `true`.
    return !file_existed
end

"""
    package(src_dir::AbstractString, tarball_path::AbstractString;
            verbose::Bool = false)

Compress `src_dir` into a tarball located at `tarball_path`.
"""
function package(src_dir::AbstractString, tarball_path::AbstractString;
                  verbose::Bool = false)
    # For now, use environment variables to set the gzip compression factor to
    # level 9, eventually there will be new enough versions of tar everywhere
    # to use -I 'gzip -9', or even to switch over to .xz files.
    withenv("GZIP" => "-9") do
        oc = OutputCollector(gen_package_cmd(src_dir, tarball_path); verbose=verbose)
        try
            if !wait(oc)
                error()
            end
        catch e
            if isa(e, InterruptException)
                rethrow()
            end
            error("Could not package $(src_dir) into $(tarball_path)")
        end
    end
end

"""
    unpack(tarball_path::AbstractString, dest::AbstractString;
           verbose::Bool = false)

Unpack tarball located at file `tarball_path` into directory `dest`.
"""
function unpack(tarball_path::AbstractString, dest::AbstractString;
                verbose::Bool = false)

    # unpack into dest
    mkpath(dest)

    # The user can force usage of our dereferencing workarounds for filesystems
    # that don't support symlinks, but it is also autodetected.
    copyderef = (get(ENV, "BINARYPROVIDER_COPYDEREF", "") == "true") || !probe_symlink_creation(dest)

    # If we should "copyderef" what we do is to unpack everything except symlinks
    # then copy the sources of the symlinks to the destination of the symlink instead.
    # This is to work around filesystems that are mounted (such as SMBFS filesystems)
    # that do not support symlinks.

    excludelist = nothing

    if copyderef
        symlinks = list_tarball_symlinks(tarball_path)
        if length(symlinks) > 0
            (excludelist, io) = mktemp()
            write(io, join([s[1] for s in symlinks], "\n"))
            close(io)
        end
    end

    oc = OutputCollector(gen_unpack_cmd(tarball_path, dest, excludelist); verbose=verbose)
    try
        if !wait(oc)
            error()
        end
    catch e
        if isa(e, InterruptException)
            rethrow()
        end
        error("Could not unpack $(tarball_path) into $(dest)")
    end

    if copyderef && length(symlinks) > 0
        @info("Replacing symlinks in tarball by their source files ...\n" * join(string.(symlinks),"\n"))
        for s in symlinks
            sourcefile = normpath(joinpath(dest, s[2]))
            destfile   = normpath(joinpath(dest, s[1]))

            if isfile(sourcefile)
                cp(sourcefile, destfile, force = true)
            else
                @warn("Symlink source '$sourcefile' does not exist!")
            end
        end
        rm(excludelist; force = true)
    end
end


"""
    download_verify_unpack(url::AbstractString, hash::AbstractString,
                           dest::AbstractString; tarball_path = nothing,
                           verbose::Bool = false, ignore_existence::Bool = false,
                           force::Bool = false)

Helper method to download tarball located at `url`, verify it matches the
given `hash`, then unpack it into folder `dest`.  In general, the method
`install()` should be used to download and install tarballs into a `Prefix`;
this method should only be used if the extra functionality of `install()` is
undesired.

If `tarball_path` is specified, the given `url` will be downloaded to
`tarball_path`, and it will not be removed after downloading and verification
is complete.  If it is not specified, the tarball will be downloaded to a
temporary location, and removed after verification is complete.

If `force` is specified, a verification failure will cause `tarball_path` to be
deleted (if it exists), the `dest` folder to be removed (if it exists) and the
tarball to be redownloaded and reverified.  If the verification check is failed
a second time, an exception is raised.  If `force` is not specified, a
verification failure will result in an immediate raised exception.

If `ignore_existence` is set, the tarball is unpacked even if the destination
directory already exists.

Returns `true` if a tarball was actually unpacked, `false` if nothing was
changed in the destination prefix.
"""
function download_verify_unpack(url::AbstractString,
                                hash::AbstractString,
                                dest::AbstractString;
                                tarball_path = nothing,
                                ignore_existence::Bool = false,
                                force::Bool = false,
                                verbose::Bool = false)
    # First, determine whether we should keep this tarball around
    remove_tarball = false
    if tarball_path === nothing
        remove_tarball = true

        function url_ext(url)
            url = basename(url)

            # Chop off urlparams
            qidx = findfirst(isequal('?'), url)
            if qidx !== nothing
                url = url[1:qidx]
            end

            # Try to detect extension
            dot_idx = findlast(isequal('.'), url)
            if dot_idx === nothing
                return nothing
            end

            return url[dot_idx+1:end]
        end

        # If extension of url contains a recognized extension, use it, otherwise use ".gz"
        ext = url_ext(url)
        if !(ext in ["tar", "gz", "tgz", "bz2", "xz"])
            ext = "gz"
        end

        tarball_path = "$(tempname())-download.$(ext)"
    end

    # Download the tarball; if it already existed and we needed to remove it
    # then we should remove the unpacked path as well
    should_delete = !download_verify(url, hash, tarball_path;
                                     force=force, verbose=verbose)
    if should_delete
        if verbose
            @info("Removing dest directory $(dest) as source tarball changed")
        end
        rm(dest; recursive=true, force=true)
    end

    # If the destination path already exists, don't bother to unpack
    if !ignore_existence && isdir(dest)
        if verbose
            @info("Destination directory $(dest) already exists, returning")
        end

        # Signify that we didn't do any unpacking
        return false
    end

    try
        if verbose
            @info("Unpacking $(tarball_path) into $(dest)...")
        end
        unpack(tarball_path, dest; verbose=verbose)
    finally
        if remove_tarball
            rm(tarball_path)
        end
    end

    # Signify that we did some unpacking!
    return true
end
