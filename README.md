# Dabble

The zero config D build tool.

## Building

Dabble comes with a `Makefile` to bootstrap the build. After building for the
first time using `make`, you can use the Dabble binary found in the `bin`
directory of the project home.

## Usage

    $ Dabble

Dabble will then parse the source files in the src directory to generate a
dependency tree. The results of this will then be written to the
`.dabble/modules` directory.

If dabble gets anything wrong, or the build fails when it shouldn't have, delete
the `.dabble` directory, as it does not contain any information that cannot be
regerated by dabble.

## `root_path`

The first time that dabble is run, it will try and detect the root directory of
the project. This is usually quite successfull (well it works for dabble itself)
but if it fails, just create a file named `.dabble.conf` in the root directory
of your project with the following in it

    [core]
    name=<project name>
    src_dir=<relative path to source directory>

The src path if the relative path to the directory that contains the .d files.
Dabble will try and automatically detect this, but it may get it wrong
sometimes.

## Configuration

The aim of Dabble is to not require any editing of configuration files to build
a standard D project. However, it is not uncommon for projects to require
non-standard build options. Dabble tries to support those, and build
configuration can be done in the `.dabble.conf` file. All files generated by
dabble are ini format, even if they do not carry the .ini suffix.

### Target configuration

Dabble automatically detects "root" modules; modules that only import other
modules and are not imported by any modules. These modules are linked aswell
as compiled, and the generated executable is placed in the `$ROOT_DIR/bin`
directory. The excutable name will be the name of the module, unless the module
name is `main`, in which case the executable name will be the name of the
project (the `core.name` entry in .dabble.conf). However, if a modules
executable name must be configured, you can add an entry in the `targets`
section of the `.dabble.conf` file. The following example configures dabble so
the `foo` root module will generate an executable named `foo_bar`:

    # .dabble.conf, targets section
    [targets]
    foo=foo_bar

Entries for non-root modules are ignored.