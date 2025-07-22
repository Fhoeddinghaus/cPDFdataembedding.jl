# cPDFdataembedding.jl
This small package provides functionality for embedding data into PDF files using Julia.
The data can be embedded as raw string data into the xml metadata of the PDF, or as a file attachment.


## Installation
You can install the package using Julia's package manager. Open the Julia REPL and run in package mode:
```julia
] add https://github.com/Fhoeddinghaus/cPDFdataembedding.jl.git
```
or 
```julia
] add git@github.com:Fhoeddinghaus/cPDFdataembedding.jl.git
```

## Requirements
This package requires the command line tool `cpdf` (coherentpdf) to be installed and available in your system's PATH. 
You can download it e.g. from [https://github.com/johnwhitington/cpdf-source](https://github.com/johnwhitington/cpdf-source) or install it via a package manager, e.g. via Homebrew on macOS.

## Example Usage
Sometimes we are lazy and may want to embed some data that was used to generate a PDF into the PDF itself, to have it available for later reference, to be able to reproduce the PDF and to directly link the PDF to the data used to generate it without having to keep track of the data separately.

Let's say, we have generated some data in Julia
```julia
mydata = rand(100)
```

and we plot these data using the `Plots` package
```julia
using Plots
plot(mydata)
```

and save the plot to a PDF file:
```julia
savefig("myplot.pdf")
```

Wouldn't it be nice to embed the data into the PDF file, so that we can always refer back to it?
We can do this using the `cPDFdataembedding` package in different ways:

```julia
using cPDFdataembedding

# Option 1: (probably not recommended) 
#   save data as raw string data in the PDF metadata.
#   Of course, you could convert it to JSON or base64 first, if you want to.
meta_add_raw_data!("myplot.pdf", string(mydata))

# to retrieve the data later, you can use:
meta_extract_raw_data("myplot.pdf") # array of strings

# Option 2: (recommended)
#   save data as a file attachment in the PDF.
#   This is more flexible and allows you to attach larger files and not only strings.
#   The package uses the JLD2 format to save the data, but you can also use other formats and attach the file manually.
attach_jld2!("myplot.pdf", mydata, "mydata")

# to retrieve the data later, you can use:
mydata = extract_jld2s("myplot.pdf") # returns an Dict containing all files as JLD2 objects
# or 
jld2_files = extract_jld2s("myplot.pdf", "output_dir") # saves all JLD2 files to the output_dir and returns an array of file names
```

For better reproducibility, you could also save a minimal script that reproduces the PDF using the data:
```julia
# save a script that reproduces the PDF (including the data)
script = """
using Plots
mydata = $(repr(mydata))
plot(mydata)
savefig("myplot.pdf")
"""
attach_script!("myplot.pdf", script, "reproduce_plot.jl")

# to retrieve the script later, you can use:
scripts = extract_scripts("myplot.pdf") # returns an array of scripts as strings
# or
script_files = extract_scripts("myplot.pdf", "output_dir") # saves all scripts to the output_dir and returns an array of file names
```

The script also does not need to contain the data itself, but can just refer to the data file:
```julia
script = """
using Plots
mydata = extract_jld2s("myplot.pdf")["mydata"] # assuming the data is attached under the name "mydata"
plot(mydata)
savefig("myplot.pdf")
"""
```


Alternatively, you can also use the `attach_file!` function to attach any file to the PDF, e.g. a CSV file with the data:
```julia
attach_file!("myplot.pdf", "mydata.csv")
```


## License
The cpdf command line tool is licensed under AGPL-3.0-only.
