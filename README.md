# simpleshader

```
gcc -o Simple Simple.cpp && mkdir -p output && rm -f output/* \
    && ./Simple && ffmpeg -i output/output-%02d.ppm -r 60 output/output.mp4
````
