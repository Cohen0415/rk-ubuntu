case "$TERM" in
  ""|unknown|vt220)
    export TERM=linux
    ;;
esac
