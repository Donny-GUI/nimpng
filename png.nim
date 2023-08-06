import streams
import zlib


type
  Pixel = tuple[r: byte, g: byte, b: byte]

type 
  PixelArray = object 
    pixels: seq[seq[Pixel]]
    width:  uint32
    height: uint32

type
  PNG = object
    filepath: cstring
    width, height: uint32
    bitDepth, colorType: byte
    idatChunks: seq[seq[byte]]


proc readIDATChunks(file: File): seq[seq[byte]] =
  var
    idatChunks: seq[seq[byte]]
    chunkType: array[4, byte]
    
  while true:
    let chunkLength = file.readU32().littleEndian
    let chunkType = file.read(4)
    let chunkData = file.read(chunkLength)
    
    if chunkType == "IDAT".cstring:
      idatChunks.add(chunkData)
    else:
      file.skip(4)  # Skip CRC

    if chunkType == "IEND".cstring:
      break  # Reached end of IDAT data

  return idatChunks

proc readPNG(filePath: cstring): PNG =
  var
    png: PNG
    file: File
    pngData: seq[byte]

  png.filepath = filePath
  file.open(filePath, fmRead)
  if not file.isOpen:
    discard

  # Read and validate the PNG signature
  pngData = file.read(8)
  if pngData != [137, 80, 78, 71, 13, 10, 26, 10]:
    discard

  var
    chunkLength: uint32
    chunkType: array[4, byte]
    ihdrData: seq[byte]

  while true:
    chunkLength = file.readU32().littleEndian
    chunkType = file.read(4)
    
    if chunkType == "IHDR".cstring:
      ihdrData = file.read(chunkLength)
      png.width = ihdrData[0..3].toU32().littleEndian
      png.height = ihdrData[4..7].toU32().littleEndian
      png.bitDepth = ihdrData[8]
      png.colorType = ihdrData[9]
    elif chunkType == "IDAT".cstring:
      png.idatChunks = readIDATChunks(file)
    else:
      file.skip(chunkLength + 4)  # Skip this chunk

    if chunkType == "IEND".cstring:
      break  # Reached end of PNG data

  file.close()
  return png

proc getPixelData(png: PNG): seq[seq[tuple[r: byte, g: byte, b: byte]]] =
  var
    pixelData: seq[seq[tuple[r: byte, g: byte, b: byte]]]
    decompressedData = decompressIDATChunks(png.idatChunks)

  for y in 0..<png.height:
    var row: seq[tuple[r: byte, g: byte, b: byte]] = newSeq[tuple[r: byte, g: byte, b: byte]](png.width)
    var rowPos = y * (png.width * 4 + 1)  # +1 for filter byte

    for x in 0..<png.width:
      let r = decompressedData[rowPos + x * 4]
      let g = decompressedData[rowPos + x * 4 + 1]
      let b = decompressedData[rowPos + x * 4 + 2]
      row[x] = (r, g, b)

    pixelData.pixels.add(row)
  pixelData.width = len(pixels[0])
  pixelData.height = len(pixels)

  return pixelData

proc decompressIDATChunks(idatChunks: seq[seq[byte]]): seq[byte] =
  var decompressedData: seq[byte]
  for chunkData in idatChunks:
    let decompressedChunk = uncompressZlib(chunkData)
    decompressedData.add(decompressedChunk)
  return decompressedData

proc createPixelArray(filePath: cstring): PixelArray =
  # create a two dimensional array of pixel data from a filepath
  var
    pngData: seq[byte]
    file: File
    width, height: uint32
    colorType, bitDepth: byte
    idatChunks: seq[seq[byte]]

  file.open(filePath, fmRead)
  if not file.isOpen:
    discard

  # Read and validate the PNG signature
  pngData = file.read(8)
  if pngData != [137, 80, 78, 71, 13, 10, 26, 10]:
    discard

  var
    chunkLength: uint32
    chunkType: array[4, byte]
    ihdrData: seq[byte]

  while true:
    chunkLength = file.readU32().littleEndian
    chunkType = file.read(4)
    
    if chunkType == "IHDR".cstring:
      ihdrData = file.read(chunkLength)
      width = ihdrData[0..3].toU32().littleEndian
      height = ihdrData[4..7].toU32().littleEndian
      bitDepth = ihdrData[8]
      colorType = ihdrData[9]
    elif chunkType == "IDAT".cstring:
      idatChunks = readIDATChunks(file)
    else:
      file.skip(chunkLength + 4)  # Skip this chunk

    if chunkType == "IEND".cstring:
      break  # Reached end of PNG data

  file.close()

  var
    pixelData: seq[seq[Pixel]]
    decompressedData = decompressIDATChunks(idatChunks)

  for y in 0..<height:
    var row: seq[Pixel] = newSeq[Pixel](width)
    var rowPos = y * (width * 4 + 1)  # +1 for filter byte

    for x in 0..<width:
      let r = decompressedData[rowPos + x * 4]
      let g = decompressedData[rowPos + x * 4 + 1]
      let b = decompressedData[rowPos + x * 4 + 2]
      row[x] = (r, g, b)

    pixelData.add(row)

  return pixelData


proc flattenPixels(pixels: seq[seq[Pixel]]): seq[byte] =
  var flattenedData: seq[byte]
  for row in pixels:
    for pixel in row:
      flattenedData.add(pixel.r)
      flattenedData.add(pixel.g)
      flattenedData.add(pixel.b)
  return flattenedData


proc toPNG(pixels: PixelArray, filePath: cstring) =
  var
    file: File
    width: int = len(PixelArray[0])
    height: int = len(PixelArray)
    flattenedData = flattenPixels(pixels)
    compressedData: seq[byte]
    idatChunk: seq[byte]

  
  file.open(filePath, fmWrite)
  if not file.isOpen:
    discard

  # Write PNG signature
  file.write([137, 80, 78, 71, 13, 10, 26, 10])

  # Write IHDR chunk (modify as needed)
  var ihdrChunk: seq[byte]
  ihdrChunk.add 0  # Width (4 bytes)
  ihdrChunk.add 0
  ihdrChunk.add 0
  ihdrChunk.add 0
  ihdrChunk.add 0  # Height (4 bytes)
  ihdrChunk.add 0
  ihdrChunk.add 0
  ihdrChunk.add 0
  ihdrChunk.add 8  # Bit depth (1 byte)
  ihdrChunk.add 2  # Color type (1 byte, RGB)
  ihdrChunk.add 0  # Compression method (1 byte)
  ihdrChunk.add 0  # Filter method (1 byte)
  ihdrChunk.add 0  # Interlace method (1 byte)
  file.writeU32(ihdrChunk.len.toUInt32().littleEndian)
  file.write("IHDR".cstring)
  file.write(ihdrChunk)
  file.writeU32(0xDEADBEEF)  # CRC placeholder

  # Compress the flattened data
  compressedData = compressZlib(flattenedData)

  # Write IDAT chunk(s)
  for chunk in compressedData:
    idatChunk = chunk[0..min(0xFFFF, chunk.len - 1)]  # Chunk size is 2 bytes
    file.writeU32(idatChunk.len.toUInt32().littleEndian)
    file.write("IDAT".cstring)
    file.write(idatChunk)
    file.writeU32(0xDEADBEEF)  # CRC placeholder

  # Write IEND chunk
  file.writeU32(0)
  file.write("IEND".cstring)
  file.writeU32(0xAE426082)  # CRC for IEND

  file.close()
    
