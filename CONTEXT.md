# PDFlight

PDFlight is a paper-reading workspace that keeps local PDF identity separate from the names readers use to organize papers.

## Language

**Paper file name**:
The name of the PDF on disk, used to locate and open the file. It is not changed by library organization.
_Avoid_: Paper title, alias

**Display alias**:
The reader-facing name shown and searched in the paper library. It is automatically derived from the paper file name until the reader supplies a custom value.
_Avoid_: File rename, paper file name

**Collection**:
A reader-created library group that can contain papers and nested collections.
_Avoid_: Folder, directory

**Unfiled**:
The virtual library group containing papers that are not assigned to a collection.
_Avoid_: Default folder
